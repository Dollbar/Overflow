#!/usr/bin/env python3
"""Generate the controlled KD28 SRAM wrappers, black boxes, Liberty, and manifest.

Command: ``python3 scripts/generate_kd28_sram_library.py``.
Outputs: fixed-cell Verilog, source lists, three synthetic Liberty files, and a checksum manifest.
Next: run ``make kd28-sram-fifo`` and ``make sta-kd28`` before consuming the generated views.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
MODEL_ROOT = ROOT / "Library" / "models" / "kd28" / "sram"
TIMING_ROOT = ROOT / "Library" / "timing" / "kd28" / "sram"
MACRO_PATH = MODEL_ROOT / "macros.yaml"
PROFILE_PATH = TIMING_ROOT / "profiles.yaml"
CELLS_PATH = MODEL_ROOT / "rtl" / "kd28_sram_cells.v"
BLACKBOX_PATH = MODEL_ROOT / "rtl" / "kd28_sram_blackboxes.v"
MODEL_FILELIST_PATH = MODEL_ROOT / "kd28_sram_models.f"
BLACKBOX_FILELIST_PATH = MODEL_ROOT / "kd28_sram_blackboxes.f"
MANIFEST_PATH = TIMING_ROOT / "manifest.yaml"


def address_width(depth: int) -> int:
    """Return the exact integer address width for a positive power-of-two depth."""
    if depth < 2 or depth & (depth - 1):
        raise ValueError(f"KD28 fixed macro depth must be a power of two: {depth}")
    return (depth - 1).bit_length()


def controlled_macros(config: dict) -> list[dict]:
    """Flatten and validate the family-oriented macro configuration."""
    macros: list[dict] = []
    for family, family_config in config["families"].items():
        if family not in {"SP", "SDP", "TDP"}:
            raise ValueError(f"unsupported KD28 SRAM family: {family}")
        for entry in family_config["macros"]:
            depth = int(entry["depth"])
            width = int(entry["width"])
            if width < 8 or width % 8:
                raise ValueError(f"KD28 fixed macro width must contain whole bytes: {width}")
            macros.append(
                {
                    "family": family,
                    "depth": depth,
                    "width": width,
                    "addr_width": address_width(depth),
                    "mask_width": width // 8,
                    "name": f"KD28_SRAM_{family}_{depth}X{width}",
                }
            )
    names = [macro["name"] for macro in macros]
    if len(names) != len(set(names)):
        raise ValueError("KD28 fixed macro names must be unique")
    return macros


def sp_ports(macro: dict) -> list[tuple[str, str, str]]:
    """Return Verilog direction, declaration, and role for an SP fixed cell."""
    aw = macro["addr_width"]
    width = macro["width"]
    mask = macro["mask_width"]
    return [
        ("input", "wire CLK", "Receive the synchronous SRAM clock."),
        ("input", "wire CS", "Enable one SRAM operation."),
        ("input", "wire WE", "Select write when high and read when low."),
        ("input", f"wire [{aw - 1}:0] A", "Select the SRAM word address."),
        ("input", f"wire [{width - 1}:0] D", "Receive write data."),
        ("input", f"wire [{mask - 1}:0] WM", "Enable active-high byte writes."),
        ("output", f"wire [{width - 1}:0] Q", "Return the registered read word."),
    ]


def sdp_ports(macro: dict) -> list[tuple[str, str, str]]:
    """Return Verilog direction, declaration, and role for an SDP fixed cell."""
    aw = macro["addr_width"]
    width = macro["width"]
    mask = macro["mask_width"]
    return [
        ("input", "wire WCLK", "Receive the synchronous write clock."),
        ("input", "wire WCS", "Enable one write operation."),
        ("input", f"wire [{aw - 1}:0] WA", "Select the write word address."),
        ("input", f"wire [{width - 1}:0] D", "Receive write data."),
        ("input", f"wire [{mask - 1}:0] WM", "Enable active-high byte writes."),
        ("input", "wire RCLK", "Receive the synchronous read clock."),
        ("input", "wire RCS", "Enable one registered read operation."),
        ("input", f"wire [{aw - 1}:0] RA", "Select the read word address."),
        ("output", f"wire [{width - 1}:0] Q", "Return the registered read word."),
    ]


def tdp_ports(macro: dict) -> list[tuple[str, str, str]]:
    """Return Verilog direction, declaration, and role for a TDP fixed cell."""
    aw = macro["addr_width"]
    width = macro["width"]
    mask = macro["mask_width"]
    return [
        ("input", "wire CLK", "Receive the shared synchronous SRAM clock."),
        ("input", "wire ACS", "Enable one port A operation."),
        ("input", "wire AWE", "Select a port A write when high."),
        ("input", f"wire [{aw - 1}:0] AA", "Select the port A word address."),
        ("input", f"wire [{width - 1}:0] AD", "Receive port A write data."),
        ("input", f"wire [{mask - 1}:0] AWM", "Enable active-high port A byte writes."),
        ("output", f"wire [{width - 1}:0] AQ", "Return the registered port A read word."),
        ("input", "wire BCS", "Enable one port B operation."),
        ("input", "wire BWE", "Select a port B write when high."),
        ("input", f"wire [{aw - 1}:0] BA", "Select the port B word address."),
        ("input", f"wire [{width - 1}:0] BD", "Receive port B write data."),
        ("input", f"wire [{mask - 1}:0] BWM", "Enable active-high port B byte writes."),
        ("output", f"wire [{width - 1}:0] BQ", "Return the registered port B read word."),
    ]


def ports_for(macro: dict) -> list[tuple[str, str, str]]:
    """Select the fixed-cell port list for one macro family."""
    return {"SP": sp_ports, "SDP": sdp_ports, "TDP": tdp_ports}[macro["family"]](macro)


def verilog_header(description: str) -> list[str]:
    """Return a deterministic Verilog-2001 generated-file header."""
    return [
        "`timescale 1ns/1ps // Define simulation time units for generated KD28 cells.",
        "`default_nettype none // Reject accidental implicit nets in generated KD28 cells.",
        "",
        f"// Generated by scripts/generate_kd28_sram_library.py; {description}",
        "// Source inputs are Library/models/kd28/sram/macros.yaml and Library/timing/kd28/sram/profiles.yaml.",
        "",
    ]


def module_declaration(macro: dict, black_box: bool) -> list[str]:
    """Render one fixed-cell Verilog module declaration."""
    prefix = "(* black_box *) " if black_box else ""
    lines = [f"{prefix}module {macro['name']} ( // Define the fixed {macro['family']} KD28 SRAM cell."]
    ports = ports_for(macro)
    for index, (direction, declaration, role) in enumerate(ports):
        comma = "," if index + 1 < len(ports) else ""
        lines.append(f"    {direction} {declaration}{comma} // {role}")
    lines.append("); // End the fixed KD28 SRAM cell interface.")
    return lines


def behavioral_instance(macro: dict) -> list[str]:
    """Render one generic-model instance beneath a fixed cell."""
    width = macro["width"]
    depth = macro["depth"]
    aw = macro["addr_width"]
    mask = macro["mask_width"]
    family = macro["family"]
    lines = [
        f"    kd28_sram_{family.lower()}_model #( // Bind the fixed cell to the portable {family} behavior.",
        f"        .DATA_WIDTH({width}), // Fix the generated data width.",
        f"        .DEPTH({depth}), // Fix the generated word depth.",
        f"        .ADDR_WIDTH({aw}), // Fix the generated address width.",
        f"        .MASK_WIDTH({mask}) // Fix the generated byte-mask width.",
        "    ) u_model ( // Instantiate the portable SRAM behavior.",
    ]
    mappings = {
        "SP": [
            ("clk_i", "CLK"), ("cs_i", "CS"), ("we_i", "WE"), ("addr_i", "A"),
            ("wdata_i", "D"), ("wmask_i", "WM"), ("rdata_o", "Q"),
        ],
        "SDP": [
            ("write_clk_i", "WCLK"), ("write_cs_i", "WCS"), ("write_addr_i", "WA"),
            ("write_data_i", "D"), ("write_mask_i", "WM"), ("read_clk_i", "RCLK"),
            ("read_cs_i", "RCS"), ("read_addr_i", "RA"), ("read_data_o", "Q"),
        ],
        "TDP": [
            ("clk_i", "CLK"), ("a_cs_i", "ACS"), ("a_we_i", "AWE"), ("a_addr_i", "AA"),
            ("a_wdata_i", "AD"), ("a_wmask_i", "AWM"), ("a_rdata_o", "AQ"),
            ("b_cs_i", "BCS"), ("b_we_i", "BWE"), ("b_addr_i", "BA"),
            ("b_wdata_i", "BD"), ("b_wmask_i", "BWM"), ("b_rdata_o", "BQ"),
        ],
    }[family]
    for index, (formal, actual) in enumerate(mappings):
        comma = "," if index + 1 < len(mappings) else ""
        lines.append(f"        .{formal}({actual}){comma} // Connect {formal} to the fixed-cell {actual} pin.")
    lines.append("    ); // End the portable SRAM behavior instance.")
    return lines


def generate_verilog(macros: list[dict]) -> None:
    """Generate behavioral fixed cells and mutually exclusive black boxes."""
    cells = verilog_header("compile this file for functional simulation only.")
    blackboxes = verilog_header("compile this file for synthesis or STA only.")
    for macro in macros:
        cells.extend(module_declaration(macro, black_box=False))
        cells.extend(behavioral_instance(macro))
        cells.append(f"endmodule // End the {macro['name']} functional cell.")
        cells.append("")
        blackboxes.extend(module_declaration(macro, black_box=True))
        blackboxes.append(f"endmodule // End the {macro['name']} black-box cell.")
        blackboxes.append("")
    cells.append("`default_nettype wire // Restore implicit-net behavior after generated functional cells.")
    blackboxes.append("`default_nettype wire // Restore implicit-net behavior after generated black boxes.")
    CELLS_PATH.write_text("\n".join(cells) + "\n", encoding="ascii")
    BLACKBOX_PATH.write_text("\n".join(blackboxes) + "\n", encoding="ascii")
    MODEL_FILELIST_PATH.write_text(
        "\n".join(
            [
                "Library/models/kd28/sram/rtl/kd28_sram_sp_model.v",
                "Library/models/kd28/sram/rtl/kd28_sram_sdp_model.v",
                "Library/models/kd28/sram/rtl/kd28_sram_tdp_model.v",
                "Library/models/kd28/sram/rtl/kd28_sram_cells.v",
            ]
        )
        + "\n",
        encoding="ascii",
    )
    BLACKBOX_FILELIST_PATH.write_text(
        "Library/models/kd28/sram/rtl/kd28_sram_blackboxes.v\n",
        encoding="ascii",
    )


def liberty_scalar_timing(clock: str, setup: float, hold: float) -> str:
    """Render setup and hold timing groups for one scalar input pin."""
    return (
        f'timing () {{ related_pin : "{clock}"; timing_type : setup_rising; '
        f'rise_constraint (kd28_constraint) {{ values ("{setup:.3f}"); }} '
        f'fall_constraint (kd28_constraint) {{ values ("{setup:.3f}"); }} }} '
        f'timing () {{ related_pin : "{clock}"; timing_type : hold_rising; '
        f'rise_constraint (kd28_constraint) {{ values ("{hold:.3f}"); }} '
        f'fall_constraint (kd28_constraint) {{ values ("{hold:.3f}"); }} }}'
    )


def liberty_output_timing(clock: str, delay: float) -> str:
    """Render clock-to-output timing for one scalar or bus output."""
    return (
        f'timing () {{ related_pin : "{clock}"; timing_type : rising_edge; '
        f'cell_rise (kd28_delay) {{ values ("{delay:.3f}"); }} '
        f'cell_fall (kd28_delay) {{ values ("{delay:.3f}"); }} '
        f'rise_transition (kd28_delay) {{ values ("{delay / 2:.3f}"); }} '
        f'fall_transition (kd28_delay) {{ values ("{delay / 2:.3f}"); }} }}'
    )


def liberty_pin(name: str, direction: str, timing: str = "", clock: bool = False) -> str:
    """Render one scalar Liberty pin."""
    clock_attr = " clock : true;" if clock else ""
    timing_attr = f" {timing}" if timing else ""
    return f"    pin ({name}) {{ direction : {direction}; capacitance : 0.001;{clock_attr}{timing_attr} }}"


def liberty_bus(name: str, width: int, direction: str, timing: str = "") -> str:
    """Render one Liberty bus using a generated width-specific type."""
    timing_attr = f" {timing}" if timing else ""
    return (
        f"    bus ({name}) {{ bus_type : kd28_bus_{width}; direction : {direction}; "
        f"capacitance : 0.001;{timing_attr} }}"
    )


def liberty_cell(macro: dict, setup: float, hold: float, delay: float) -> list[str]:
    """Render one fixed SRAM Liberty cell with scalar timing tables."""
    width = macro["width"]
    aw = macro["addr_width"]
    mask = macro["mask_width"]
    family = macro["family"]
    lines = [f"  cell ({macro['name']}) {{", "    area : 0.0;", "    is_macro_cell : true;"]
    if family == "SP":
        input_timing = liberty_scalar_timing("CLK", setup, hold)
        lines.extend(
            [
                liberty_pin("CLK", "input", clock=True),
                liberty_pin("CS", "input", input_timing),
                liberty_pin("WE", "input", input_timing),
                liberty_bus("A", aw, "input", input_timing),
                liberty_bus("D", width, "input", input_timing),
                liberty_bus("WM", mask, "input", input_timing),
                liberty_bus("Q", width, "output", liberty_output_timing("CLK", delay)),
            ]
        )
    elif family == "SDP":
        write_timing = liberty_scalar_timing("WCLK", setup, hold)
        read_timing = liberty_scalar_timing("RCLK", setup, hold)
        lines.extend(
            [
                liberty_pin("WCLK", "input", clock=True),
                liberty_pin("WCS", "input", write_timing),
                liberty_bus("WA", aw, "input", write_timing),
                liberty_bus("D", width, "input", write_timing),
                liberty_bus("WM", mask, "input", write_timing),
                liberty_pin("RCLK", "input", clock=True),
                liberty_pin("RCS", "input", read_timing),
                liberty_bus("RA", aw, "input", read_timing),
                liberty_bus("Q", width, "output", liberty_output_timing("RCLK", delay)),
            ]
        )
    else:
        input_timing = liberty_scalar_timing("CLK", setup, hold)
        lines.extend(
            [
                liberty_pin("CLK", "input", clock=True),
                liberty_pin("ACS", "input", input_timing),
                liberty_pin("AWE", "input", input_timing),
                liberty_bus("AA", aw, "input", input_timing),
                liberty_bus("AD", width, "input", input_timing),
                liberty_bus("AWM", mask, "input", input_timing),
                liberty_bus("AQ", width, "output", liberty_output_timing("CLK", delay)),
                liberty_pin("BCS", "input", input_timing),
                liberty_pin("BWE", "input", input_timing),
                liberty_bus("BA", aw, "input", input_timing),
                liberty_bus("BD", width, "input", input_timing),
                liberty_bus("BWM", mask, "input", input_timing),
                liberty_bus("BQ", width, "output", liberty_output_timing("CLK", delay)),
            ]
        )
    lines.append("  }")
    return lines


def generate_liberty(macros: list[dict], profiles: dict) -> list[Path]:
    """Generate one complete synthetic Liberty library per timing scenario."""
    widths = sorted(
        {macro["width"] for macro in macros}
        | {macro["addr_width"] for macro in macros}
        | {macro["mask_width"] for macro in macros}
    )
    outputs: list[Path] = []
    for scenario_name, scenario in profiles["scenarios"].items():
        setup = float(scenario["setup_ns"])
        hold = float(scenario["hold_ns"])
        delay = float(scenario["clock_to_q_ns"])
        lines = [
            f"/* Apache-2.0 generated KD28 {scenario_name} synthetic SRAM timing view. */",
            f"library (kd28_sram_{scenario_name}) {{",
            "  delay_model : table_lookup;",
            '  time_unit : "1ns";',
            '  voltage_unit : "1V";',
            '  current_unit : "1mA";',
            '  leakage_power_unit : "1nW";',
            "  capacitive_load_unit (1, pf);",
            "  nom_process : 1.0;",
            f"  nom_voltage : {float(scenario['voltage']):.3f};",
            f"  nom_temperature : {float(scenario['temperature_c']):.1f};",
            "  lu_table_template (kd28_constraint) { variable_1 : constrained_pin_transition; index_1 (\"0.050\"); }",
            "  lu_table_template (kd28_delay) { variable_1 : total_output_net_capacitance; index_1 (\"0.010\"); }",
        ]
        for width in widths:
            lines.extend(
                [
                    f"  type (kd28_bus_{width}) {{",
                    "    base_type : array;",
                    "    data_type : bit;",
                    f"    bit_width : {width};",
                    f"    bit_from : {width - 1};",
                    "    bit_to : 0;",
                    "    downto : true;",
                    "  }",
                ]
            )
        for macro in macros:
            lines.extend(liberty_cell(macro, setup, hold, delay))
        lines.append("}")
        output = TIMING_ROOT / f"kd28_sram_{scenario_name}.lib"
        output.write_text("\n".join(lines) + "\n", encoding="ascii")
        outputs.append(output)
    return outputs


def checksum(path: Path) -> str:
    """Return the SHA-256 digest for one controlled source or generated file."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate_manifest(liberty_paths: list[Path]) -> None:
    """Generate a deterministic manifest over the complete controlled package boundary."""
    controlled = [
        MACRO_PATH,
        PROFILE_PATH,
        MODEL_ROOT / "rtl" / "kd28_sram_sp_model.v",
        MODEL_ROOT / "rtl" / "kd28_sram_sdp_model.v",
        MODEL_ROOT / "rtl" / "kd28_sram_tdp_model.v",
        CELLS_PATH,
        BLACKBOX_PATH,
        ROOT / "Library" / "models" / "kd28" / "fifo" / "rtl" / "kd28_sync_fifo.v",
        ROOT / "Library" / "models" / "kd28" / "fifo" / "rtl" / "kd28_async_fifo.v",
        ROOT / "specs" / "interfaces" / "kd28_sram_fifo_v0.1.md",
        *liberty_paths,
    ]
    lines = [
        "schema_version: 1",
        "asset_id: kd28-sram-fifo-library-v0.1",
        "version: 0.1",
        "technology: KD28",
        "technology_status: repository_synthetic_not_foundry_pdk",
        "license: Apache-2.0",
        "evidence_level: ANALYTICAL",
        "validation_status: REQUIRES_LOCAL_COMMAND",
        "validation_commands:",
        "  - make kd28-sram-fifo",
        "  - make sta-kd28",
        "generation_command: python3 scripts/generate_kd28_sram_library.py",
        "checksums:",
    ]
    for path in controlled:
        lines.append(f"  {path.relative_to(ROOT).as_posix()}: {checksum(path)}")
    lines.extend(
        [
            "permitted_claims:",
            "  - fixed_cell_name_and_port_link",
            "  - portable_synchronous_sram_behavior",
            "  - parameterized_fifo_functional_behavior",
            "  - synthetic_setup_hold_and_clock_to_output_plumbing",
            "prohibited_claims:",
            "  - foundry_pvt",
            "  - physical_fmax",
            "  - silicon_area_or_power",
            "  - retention_or_yield",
            "  - signoff",
        ]
    )
    MANIFEST_PATH.write_text("\n".join(lines) + "\n", encoding="ascii")


def main() -> int:
    """Generate and checksum every controlled KD28 SRAM library artifact."""
    macro_config = yaml.safe_load(MACRO_PATH.read_text(encoding="ascii"))
    profiles = yaml.safe_load(PROFILE_PATH.read_text(encoding="ascii"))
    if macro_config["technology"] != "KD28" or profiles["technology"] != "KD28":
        raise SystemExit("KD28 source inputs must use the controlled technology name")
    macros = controlled_macros(macro_config)
    generate_verilog(macros)
    liberty_paths = generate_liberty(macros, profiles)
    generate_manifest(liberty_paths)
    print(f"[KD28_GENERATE PASS] macros={len(macros)} liberty={len(liberty_paths)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

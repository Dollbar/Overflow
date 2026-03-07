#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Run KD28 Verilator RTL simulation and Yosys fixed-black-box link checks."""

from __future__ import annotations

from pathlib import Path
import os
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / "verification" / "kd28" / "work"
RTL_WORK = WORK / "rtl"
MAPPING_WORK = WORK / "storage_map"
YOSYS_WORK = WORK / "yosys"
COMMON_SOURCES = [
    ROOT / "Library" / "models" / "kd28" / "sram" / "rtl" / "kd28_sram_sp_model.v",
    ROOT / "Library" / "models" / "kd28" / "sram" / "rtl" / "kd28_sram_sdp_model.v",
    ROOT / "Library" / "models" / "kd28" / "sram" / "rtl" / "kd28_sram_tdp_model.v",
    ROOT / "Library" / "models" / "kd28" / "sram" / "rtl" / "kd28_sram_cells.v",
    ROOT / "Library" / "models" / "kd28" / "fifo" / "rtl" / "kd28_fifo_sdp_storage_map.v",
    ROOT / "rtl" / "npu" / "sram" / "kd28_npu_sram_adapter.sv",
    ROOT / "Library" / "models" / "kd28" / "fifo" / "rtl" / "kd28_sync_fifo.v",
    ROOT / "Library" / "models" / "kd28" / "fifo" / "rtl" / "kd28_async_fifo.v",
]
VERILATOR_CASES = [
    (
        "tb_kd28_sram_fifo",
        ROOT / "verification" / "kd28" / "tb" / "tb_kd28_sram_fifo.v",
        RTL_WORK,
        "[RTL_SIM PASS] kd28_sram_fifo",
    ),
    (
        "tb_kd28_fifo_storage_map",
        ROOT / "verification" / "kd28" / "tb" / "tb_kd28_fifo_storage_map.v",
        MAPPING_WORK,
        "[RTL_SIM PASS] kd28_fifo_storage_map",
    ),
    (
        "tb_npu_kd28_sram_adapter",
        ROOT / "verification" / "kd28" / "tb" / "tb_npu_kd28_sram_adapter.sv",
        WORK / "npu_adapter",
        "[RTL_SIM PASS] npu_kd28_sram_adapter",
    ),
    (
        "tb_sram_macro_contract",
        ROOT / "verification" / "npu" / "compute" / "tb" / "tb_sram_macro_contract.sv",
        WORK / "npu_tdp_adapter",
        "PASS: SRAM 32x32/64/128 one-cycle dual-port contract",
    ),
]


def run_logged(command: list[str], log: Path) -> subprocess.CompletedProcess[str]:
    """Run one command from the repository root and retain combined output."""
    result = subprocess.run(
        command,
        cwd=ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    log.write_text(result.stdout, encoding="utf-8")
    return result


def run_verilator() -> None:
    """Compile and execute every self-checking SRAM and FIFO regression."""
    verilator = shutil.which("verilator")
    if not verilator:
        raise SystemExit("required tool was not found in PATH: verilator")
    for top, testbench, case_work, signature in VERILATOR_CASES:
        case_work.mkdir(parents=True, exist_ok=True)
        command = [
            verilator,
            "--binary",
            "--timing",
            "-j",
            os.environ.get("JOBS", "4"),
            "-Wall",
            "-Wno-DECLFILENAME",
            "-Wno-WIDTHEXPAND",
            "-Wno-WIDTHTRUNC",
            "--top-module",
            top,
            "-Mdir",
            str(case_work / "obj"),
            *[str(path) for path in COMMON_SOURCES],
            str(testbench),
        ]
        build = run_logged(command, case_work / "build.log")
        if build.returncode:
            raise SystemExit(
                f"KD28 Verilator build failed for {top}; inspect {(case_work / 'build.log').relative_to(ROOT)}"
            )
        binary = case_work / "obj" / f"V{top}"
        simulation = run_logged([str(binary)], case_work / "simulation.log")
        if simulation.returncode:
            raise SystemExit(
                f"KD28 Verilator simulation failed for {top}; inspect "
                f"{(case_work / 'simulation.log').relative_to(ROOT)}"
            )
        if signature not in simulation.stdout:
            raise SystemExit(f"KD28 Verilator simulation omitted its pass signature for {top}")
        print(signature)


def run_yosys_link() -> None:
    """Prove that all fixed black-box names and ports elaborate under a generic synthesis front end."""
    yosys = shutil.which("yosys")
    if not yosys:
        raise SystemExit("required tool was not found in PATH: yosys")
    YOSYS_WORK.mkdir(parents=True, exist_ok=True)
    blackboxes = ROOT / "Library" / "models" / "kd28" / "sram" / "rtl" / "kd28_sram_blackboxes.v"
    smoke = ROOT / "technology" / "kd28" / "smoke" / "kd28_sta_smoke_top.v"
    script = (
        f"read_verilog -lib {blackboxes}; "
        f"read_verilog {smoke}; "
        "hierarchy -check -top kd28_sta_smoke_top; "
        "proc; check -assert"
    )
    result = run_logged([yosys, "-q", "-p", script], YOSYS_WORK / "link.log")
    if result.returncode:
        raise SystemExit(f"KD28 Yosys link failed; inspect {(YOSYS_WORK / 'link.log').relative_to(ROOT)}")
    print("[GENERIC_SYNTH PASS] kd28_fixed_blackbox_link")

    mapper = ROOT / "Library" / "models" / "kd28" / "fifo" / "rtl" / "kd28_fifo_sdp_storage_map.v"
    sync_fifo = ROOT / "Library" / "models" / "kd28" / "fifo" / "rtl" / "kd28_sync_fifo.v"
    async_fifo = ROOT / "Library" / "models" / "kd28" / "fifo" / "rtl" / "kd28_async_fifo.v"
    mapping_smoke = ROOT / "technology" / "kd28" / "smoke" / "kd28_fifo_mapping_smoke_top.v"
    mapping_script = (
        f"read_verilog -lib {blackboxes}; "
        f"read_verilog {mapper} {sync_fifo} {async_fifo} {mapping_smoke}; "
        "hierarchy -check -top kd28_fifo_mapping_smoke_top; "
        "proc; opt_clean; "
        "select -assert-count 2 t:KD28_SRAM_SDP_256X32; "
        "select -assert-count 1 t:KD28_SRAM_SDP_512X64; "
        "select -assert-count 1 t:KD28_SRAM_SDP_1024X128; "
        "select -assert-count 4 t:KD28_SRAM_SDP_2048X256; "
        "select -assert-none t:$mem_v2; "
        "check -assert"
    )
    mapping_result = run_logged([yosys, "-q", "-p", mapping_script], YOSYS_WORK / "fifo_mapping.log")
    if mapping_result.returncode:
        raise SystemExit(
            f"KD28 mapped FIFO synthesis failed; inspect {(YOSYS_WORK / 'fifo_mapping.log').relative_to(ROOT)}"
        )
    print("[GENERIC_SYNTH PASS] kd28_fifo_fixed_macro_mapping")

    npu_adapter = ROOT / "rtl" / "npu" / "sram" / "kd28_npu_sram_adapter.sv"
    npu_smoke = ROOT / "technology" / "kd28" / "smoke" / "npu_kd28_sram_mapping_smoke_top.sv"
    npu_mapping_script = (
        f"read_verilog -lib {blackboxes}; "
        f"read_verilog -sv {mapper} {npu_adapter} {npu_smoke}; "
        "hierarchy -check -top npu_kd28_sram_mapping_smoke_top; "
        "proc; flatten; opt_clean; "
        "select -assert-count 18 t:KD28_SRAM_SDP_256X32; "
        "select -assert-count 16 t:KD28_SRAM_SDP_2048X256; "
        "select -assert-count 1 t:KD28_SRAM_TDP_32X32; "
        "select -assert-count 1 t:KD28_SRAM_TDP_32X64; "
        "select -assert-count 1 t:KD28_SRAM_TDP_32X128; "
        "select -assert-none t:$mem_v2; "
        "check -assert"
    )
    npu_mapping_result = run_logged(
        [yosys, "-q", "-p", npu_mapping_script],
        YOSYS_WORK / "npu_sram_mapping.log",
    )
    if npu_mapping_result.returncode:
        raise SystemExit(
            "KD28 mapped NPU SRAM synthesis failed; inspect "
            f"{(YOSYS_WORK / 'npu_sram_mapping.log').relative_to(ROOT)}"
        )
    print("[GENERIC_SYNTH PASS] npu_kd28_fixed_macro_mapping")


def main() -> int:
    """Run every mandatory KD28 RTL and generic-link validation step."""
    run_verilator()
    run_yosys_link()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Run multi-corner KDLink partition and HBM/SerDes interface STA.

Command: pass one ``--corner name=LIBERTY_FILE`` per
standard-cell PVT corner, plus ``--driving-cell`` and ``--period-ns``.
Outputs: ``verification/kdlink/sta/summary.json`` and reports below the local
``work/`` directories. Next: replace the synthetic interface views with
licensed macro timing views before implementation or signoff.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / "verification" / "kdlink" / "sta" / "work"
SUMMARY = ROOT / "verification" / "kdlink" / "sta" / "summary.json"
INTERFACE_ROOT = ROOT / "Library" / "timing" / "interfaces"
INTERFACE_CORNERS = ("fast", "typical", "slow")
PARTITIONS = {
    "coll_sync_fifo": ["coll_sync_fifo.v"],
    "coll_crc32_flit_pipeline": ["coll_crc32_nibble.v", "coll_crc32_flit_pipeline.v"],
    "coll_reduction_engine": [
        "coll_lzc24.v",
        "coll_fp16_to_fp32.v",
        "coll_fp32_add_lane.v",
        "coll_fp32_to_fp16_pipeline.v",
        "coll_fp32_to_bf16.v",
        "coll_int32_reduction.v",
        "coll_reduction_engine.v",
    ],
    "kdlink_context_scheduler16": ["kdlink_context_scheduler16.v"],
    "kdlink_credit_bank8": ["kdlink_credit_bank8.v"],
    "kdlink_link_manager": ["kdlink_link_manager.v"],
    "kdlink_reverse_ctrl": [
        "coll_crc16_byte.v",
        "kdlink_reverse_codec.v",
        "kdlink_reverse_ctrl.v",
    ],
    "kdlink_pcs_deskew10": ["kdlink_pcs_deskew10.v"],
    "kdlink_bonded_tx_register": ["kdlink_bonded_tx_register.v"],
    "kdlink_switch_rr_arbiter32": ["kdlink_switch_rr_arbiter32.v"],
}


def run(command: list[str], log: Path) -> str:
    result = subprocess.run(
        command,
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(result.stdout, encoding="utf-8")
    if result.returncode:
        raise SystemExit(f"command failed; see {log.relative_to(ROOT)}")
    return result.stdout


def yosys_script(
    top: str,
    sources: list[str],
    liberty: Path,
    period_ns: float,
    corner_work: Path,
) -> str:
    reads = "\n".join(f"read_verilog -Irtl/kdlink rtl/kdlink/{source}" for source in sources)
    delay_ps = max(1, int(period_ns * 250.0))
    return "\n".join(
        [
            reads,
            f"hierarchy -check -top {top}",
            "proc; opt; fsm; opt; check -assert; async2sync; opt; memory; opt",
            "flatten; opt",
            "dffunmap; techmap",
            f"dfflibmap -liberty {liberty}",
            f"abc -D {delay_ps} -constr {corner_work / 'abc.constr'} -liberty {liberty}",
            "clean -purge",
            f"write_verilog -noattr -noexpr -nodec {corner_work / (top + '_mapped.v')}",
            f"write_json {corner_work / (top + '_mapped.json')}",
        ]
    ) + "\n"


def input_ports(top: str, corner_work: Path) -> list[str]:
    data = json.loads((corner_work / f"{top}_mapped.json").read_text(encoding="utf-8"))
    return [
        name
        for name, port in data["modules"][top]["ports"].items()
        if port["direction"] == "input" and name not in {"clk_i", "rst_n_i"}
    ]


def sta_script(
    top: str,
    liberty: Path,
    interface_liberty: Path,
    period_ns: float,
    setup_uncertainty_ns: float,
    hold_uncertainty_ns: float,
    corner_work: Path,
) -> str:
    inputs = input_ports(top, corner_work)
    lines = [
        f"read_liberty {liberty}",
        f"read_liberty {interface_liberty}",
        f"read_verilog {corner_work / (top + '_mapped.v')}",
        f"link_design {top}",
        f"create_clock -name partition_clk -period {period_ns:.3f} [get_ports clk_i]",
        f"set_clock_uncertainty -setup {setup_uncertainty_ns:.3f} [get_clocks partition_clk]",
        f"set_clock_uncertainty -hold {hold_uncertainty_ns:.3f} [get_clocks partition_clk]",
        "set_false_path -from [get_ports rst_n_i]",
    ]
    if inputs:
        lines.append(
            "set_input_delay 0.100 -clock partition_clk [get_ports {"
            + " ".join(inputs)
            + "}]"
        )
    lines.extend(
        [
            "set_output_delay 0.100 -clock partition_clk [all_outputs]",
            "set_load 0.005 [all_outputs]",
            'puts "KDLINK_MAX_BEGIN"',
            "report_checks -path_delay max -format full_clock_expanded -digits 4 -group_path_count 10",
            'puts "KDLINK_MAX_END"',
            "report_wns",
            "report_tns",
            'puts "KDLINK_MIN_BEGIN"',
            "report_checks -path_delay min -format full_clock_expanded -digits 4 -group_path_count 10",
            'puts "KDLINK_MIN_END"',
            "report_wns -min",
            "report_tns -min",
            'puts "KDLINK_STA_DONE"',
        ]
    )
    return "\n".join(lines) + "\n"


def worst_slack(text: str, begin: str, end: str, check_name: str) -> float:
    section = text.split(begin, 1)[1].split(end, 1)[0]
    values = re.findall(
        r"^\s*(-?\d+(?:\.\d+)?)\s+slack\s+\((?:MET|VIOLATED)\)",
        section,
        re.MULTILINE,
    )
    if not values:
        raise SystemExit(f"OpenSTA did not report a {check_name} path slack")
    return min(float(value) for value in values)


def parse_corner(value: str) -> tuple[str, Path]:
    name, separator, raw_path = value.partition("=")
    if not separator or name not in INTERFACE_CORNERS:
        raise argparse.ArgumentTypeError(
            "corner must be fast=/path, typical=/path, or slow=/path"
        )
    liberty = Path(raw_path).expanduser().resolve()
    if not liberty.is_file():
        raise argparse.ArgumentTypeError(f"Liberty file does not exist: {liberty}")
    return name, liberty


def validate_interface_corners(make: str) -> list[dict[str, object]]:
    expected = {
        corner: INTERFACE_ROOT / f"overflow_hbm_serdes_abstract_{corner}.lib"
        for corner in INTERFACE_CORNERS
    }
    missing = [str(path.relative_to(ROOT)) for path in expected.values() if not path.is_file()]
    if missing:
        raise SystemExit("missing interface Liberty files: " + ", ".join(missing))
    output = run([make, "-C", "technology", "sta-interfaces"], WORK / "interface_sta.log")
    results: list[dict[str, object]] = []
    for corner, liberty in expected.items():
        marker = f"[STA_INTERFACE PASS] {corner}"
        if marker not in output:
            raise SystemExit(f"interface STA omitted PASS marker for {corner}")
        results.append(
            {
                "corner": corner,
                "library_label": liberty.name,
                "library_file_distributed": True,
                "status": "PASS",
            }
        )
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--period-ns", type=float, default=1.000)
    parser.add_argument("--setup-uncertainty-ns", type=float, default=0.100)
    parser.add_argument("--hold-uncertainty-ns", type=float, default=0.020)
    parser.add_argument(
        "--corner",
        action="append",
        type=parse_corner,
        default=[],
        metavar="NAME=LIBERTY_FILE",
        help="repeat for fast, typical, and slow standard-cell PVT corners",
    )
    parser.add_argument(
        "--liberty",
        type=Path,
        help="legacy single setup-corner Liberty; prefer three --corner options",
    )
    parser.add_argument("--driving-cell", default=os.environ.get("KDLINK_DRIVING_CELL"))
    args = parser.parse_args()
    if args.period_ns <= 0.0:
        raise SystemExit("--period-ns must be greater than zero")
    if args.setup_uncertainty_ns < 0.0 or args.hold_uncertainty_ns < 0.0:
        raise SystemExit("clock uncertainty values must be nonnegative")
    if args.corner and args.liberty:
        raise SystemExit("use either repeated --corner options or legacy --liberty, not both")
    corners = dict(args.corner)
    if len(corners) != len(args.corner):
        raise SystemExit("each standard-cell corner name may be supplied only once")
    legacy_liberty = args.liberty or (
        Path(os.environ["KDLINK_SETUP_LIB"]) if "KDLINK_SETUP_LIB" in os.environ else None
    )
    if not corners and legacy_liberty is not None and legacy_liberty.is_file():
        corners = {"slow": legacy_liberty.resolve()}
    if not corners:
        raise SystemExit(
            "pass fast, typical, and slow --corner options, or use legacy KDLINK_SETUP_LIB/--liberty"
        )
    if args.corner and tuple(corner for corner in INTERFACE_CORNERS if corner in corners) != INTERFACE_CORNERS:
        raise SystemExit("multi-corner STA requires fast, typical, and slow standard-cell Liberty files")
    if not args.driving_cell or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", args.driving_cell):
        raise SystemExit("set KDLINK_DRIVING_CELL or pass --driving-cell with a valid buffer cell name")
    yosys = shutil.which("yosys")
    opensta = shutil.which("opensta") or shutil.which("sta")
    make = shutil.which("make")
    if not yosys or not opensta or not make:
        raise SystemExit("yosys, opensta, and make must be available in PATH")
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)
    interface_results = validate_interface_corners(make)
    corner_results: list[dict[str, object]] = []
    for corner in INTERFACE_CORNERS:
        if corner not in corners:
            continue
        liberty = corners[corner]
        interface_liberty = INTERFACE_ROOT / f"overflow_hbm_serdes_abstract_{corner}.lib"
        corner_work = WORK / corner
        corner_work.mkdir()
        (corner_work / "abc.constr").write_text(
            f"set_driving_cell {args.driving_cell}\nset_load 5.0\n", encoding="utf-8"
        )
        partitions: list[dict[str, object]] = []
        for top, sources in PARTITIONS.items():
            synth_script = corner_work / f"{top}.ys"
            synth_script.write_text(
                yosys_script(top, sources, liberty, args.period_ns, corner_work),
                encoding="utf-8",
            )
            run([yosys, "-s", str(synth_script)], corner_work / f"{top}_synth.log")
            tcl = corner_work / f"{top}.tcl"
            tcl.write_text(
                sta_script(
                    top,
                    liberty,
                    interface_liberty,
                    args.period_ns,
                    args.setup_uncertainty_ns,
                    args.hold_uncertainty_ns,
                    corner_work,
                ),
                encoding="utf-8",
            )
            run([opensta, str(tcl)], corner_work / f"{top}_sta.log")
            log_text = (corner_work / f"{top}_sta.log").read_text(
                encoding="utf-8", errors="replace"
            )
            if "Error:" in log_text or "KDLINK_STA_DONE" not in log_text:
                raise SystemExit(
                    f"OpenSTA error; see {(corner_work / f'{top}_sta.log').relative_to(ROOT)}"
                )
            setup_slack = worst_slack(
                log_text, "KDLINK_MAX_BEGIN", "KDLINK_MAX_END", "setup"
            )
            hold_slack = worst_slack(
                log_text, "KDLINK_MIN_BEGIN", "KDLINK_MIN_END", "hold"
            )
            critical_period = args.period_ns - setup_slack
            status = "PASS" if setup_slack >= 0.0 and hold_slack >= 0.0 else "FAIL"
            partitions.append(
                {
                    "module": top,
                    "period_ns": args.period_ns,
                    "setup_slack_ns": setup_slack,
                    "hold_slack_ns": hold_slack,
                    "critical_period_ns": round(critical_period, 4),
                    "estimated_fmax_mhz": round(1000.0 / critical_period, 1),
                    "status": status,
                }
            )
            print(
                f"[STA {status}] {corner}/{top} "
                f"setup={setup_slack:.4f} ns hold={hold_slack:.4f} ns"
            )
        corner_results.append(
            {
                "corner": corner,
                "standard_cell_library_label": liberty.name,
                "standard_cell_library_distributed": False,
                "interface_library_label": interface_liberty.name,
                "interface_library_distributed": True,
                "partitions": partitions,
                "status": "PASS" if all(item["status"] == "PASS" for item in partitions) else "FAIL",
            }
        )
    passed = all(item["status"] == "PASS" for item in corner_results)
    summary = {
        "schema_version": 2,
        "evidence": "STA_PRE_LAYOUT_CELL_DELAY",
        "target_period_ns": args.period_ns,
        "target_frequency_mhz": round(1000.0 / args.period_ns, 1),
        "setup_clock_uncertainty_ns": args.setup_uncertainty_ns,
        "hold_clock_uncertainty_ns": args.hold_uncertainty_ns,
        "driving_cell": args.driving_cell,
        "interface_sta": {
            "evidence": "ANALYTICAL_SYNTHETIC_INTERFACE_TIMING",
            "corners": interface_results,
            "status": "PASS",
        },
        "corners": corner_results,
        "limitations": [
            "no extracted interconnect parasitics or clock tree",
            "synthetic HBM/SerDes interface views are not vendor macro characterization",
            "memory arrays, switch VOQs, PHY hard macros, and analog SerDes excluded",
            "no flat endpoint, fabric, or chip timing claim",
        ],
        "pass": passed,
    }
    SUMMARY.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    if not passed:
        raise SystemExit("one or more KDLink timing partitions failed the target period")


if __name__ == "__main__":
    main()

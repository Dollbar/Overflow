"""Run: python3 verification/tl_prepared_partition/run_timing.py --lib-root PATH --sta PATH.
Optional --candidate FILE, --dependency-root DIR and --label NAME. Produces actual mapped netlists,
five-corner/two-period STA, source/library hashes and raw logs under
build/verification/tl_prepared_partition. Next close registered RTL/mapped equivalence;
the old four-cursor-state checker does not cover this new interface and state.
Exit 1 retains completed measurements with timing violations.
"""
from pathlib import Path
import argparse
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "verification/tl_partition_mapping"))
from run_cec import dump, execute, need, sha
from scripts.check_sta_report import check_report

CORNERS = ("tt0p9v25c", "ssg0p81v125c", "ssg0p81vm40c", "ffg0p99v125c", "ffg0p99vm40c")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lib-root", type=Path, required=True)
    parser.add_argument("--sta", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, default=ROOT / "rtl/tl/tl_prepared_partition.v")
    parser.add_argument("--label", default="timing")
    parser.add_argument("--dependency-root", type=Path, help="optional candidate decoder/admission directory")
    args = parser.parse_args()
    need(re.fullmatch(r"[a-zA-Z0-9_-]+", args.label), "invalid label")
    libraries = {c: args.lib_root.resolve() / ("tcbn28hpcplusbwp40p140" + c + ".lib") for c in CORNERS}
    need(all(p.is_file() for p in (*libraries.values(), args.sta, args.candidate)), "missing actual process input")
    stage = ROOT / "build/verification/tl_prepared_partition" / args.label
    stage.mkdir(parents=True, exist_ok=False)
    dependency_root = (args.dependency_root or ROOT / "rtl/tl").resolve()
    sources = [dependency_root / n for n in ("tl_control_decode.v", "tl_control_tenure.v")]
    sources += [ROOT / "scripts" / n for n in ("map_tl_prepared_partition.tcl", "sta_tl_prepared_partition.tcl", "credit_abc.constr", "check_sta_report.py")]
    result = {"candidate_sha256": sha(args.candidate), "complete": False, "widths": [],
              "sources": {str(p): sha(p) for p in sources},
              "libraries": {c: {"path": str(p), "sha256": sha(p)} for c, p in libraries.items()}}
    (stage / "candidate.v").write_bytes(args.candidate.read_bytes())
    (stage / "runner.py").write_bytes(Path(__file__).read_bytes())
    dump(stage / "results.json", result)
    for width in (8, 16):
        folder = stage / f"width{width}"
        folder.mkdir()
        script = (ROOT / "scripts/map_tl_prepared_partition.tcl").read_text()
        script = script.replace("set root [file dirname [file dirname [file normalize [info script]]]]", "set root {" + str(ROOT) + "}")
        script = script.replace("yosys read_verilog [file join $root rtl tl $name.v]", 'if {$name eq "tl_prepared_partition"} {yosys read_verilog {' + str(stage / "candidate.v") + '}} else {yosys read_verilog [file join $root rtl tl $name.v]}')
        script = script.replace("[file join $root rtl tl $name.v]", "[file join {" + str(dependency_root) + "} $name.v]")
        script = "".join(f"set env({k}) {{{v}}}\n" for k, v in {"UALINK_LIBERTY": libraries["ssg0p81v125c"], "UALINK_WIDTH": width, "UALINK_BUILD_DIR": folder}.items()) + script
        (folder / "map.tcl").write_text(script)
        row = {"width": width, "mapping": execute(["yosys", "-Q", "-T", "-c", str(folder / "map.tcl")], folder / "map.log", 600), "sta": []}
        result["widths"].append(row)
        dump(stage / "results.json", result)
        if row["mapping"]["exit"]:
            continue
        row["netlist_sha256"] = sha(folder / "mapped.v")
        for corner, library in libraries.items():
            for period in ("0.640", "6.400"):
                name = corner + "_" + period
                script = "".join(f"set env({k}) {{{v}}}\n" for k, v in {"UALINK_LIBERTY": library, "UALINK_NETLIST": folder / "mapped.v", "UALINK_PERIOD_NS": period}.items())
                script += "source {" + str(ROOT / "scripts/sta_tl_prepared_partition.tcl") + "}\n"
                (folder / (name + ".tcl")).write_text(script)
                measured = execute([str(args.sta.resolve()), "-exit", str(folder / (name + ".tcl"))], folder / (name + ".log"), 120)
                log = (folder / (name + ".log")).read_text()
                values = re.findall(r"^worst slack max\s+(\S+)", log, re.M)
                measured.update(corner=corner, period_ns=float(period), setup_slack_ns=float(values[0]) if len(values) == 1 else None)
                try:
                    check_report(log, design="prepared_partition")
                    measured["report_gate"] = measured["exit"] == 0
                except ValueError as error:
                    measured.update(report_gate=False, diagnostic=str(error))
                row["sta"].append(measured)
                dump(stage / "results.json", result)
        print(width, "measurement complete", flush=True)
    result["complete"] = True
    result["sources_unchanged"] = all(sha(ROOT / name) == digest for name, digest in result["sources"].items())
    result["all_sta_passed"] = result["sources_unchanged"] and len(result["widths"]) == 2 and all(r["mapping"]["exit"] == 0 and len(r["sta"]) == 10 and all(s["report_gate"] for s in r["sta"]) for r in result["widths"])
    dump(stage / "results.json", result)
    return 0 if result["all_sta_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

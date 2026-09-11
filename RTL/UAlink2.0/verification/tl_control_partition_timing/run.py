"""Run: python3 verification/tl_control_partition_timing/run.py --lib-root PATH --sta PATH.

Outputs: private build/verification/tl_control_partition_timing/<label>/ logs,
mapped artifacts and results.json with exact input hashes and real exit codes.
Next: audit failed paths, preserve these baselines, then optimize with equivalence.
This measures one block with ideal clocks and no extracted wire parasitics.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.check_sta_report import check_report

CORNERS = ("tt0p9v25c", "ssg0p81v125c", "ssg0p81vm40c",
           "ffg0p99v125c", "ffg0p99vm40c")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lib-root", type=Path, required=True)
    parser.add_argument("--sta", type=Path, required=True)
    parser.add_argument("--label", default="baseline")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", args.label):
        parser.error("label must be a single portable directory name")
    libs = {c: args.lib_root.resolve() / ("tcbn28hpcplusbwp40p140" + c + ".lib")
            for c in CORNERS}
    for p in (*libs.values(), args.sta.resolve()):
        if not p.is_file():
            parser.error(f"missing input: {p}")
    stage = ROOT / "build/verification/tl_control_partition_timing" / args.label
    stage.mkdir(parents=True, exist_ok=False)
    sources = [ROOT / "rtl/tl" / (n + ".v") for n in
               ("tl_control_partition", "tl_credit_admission", "tl_control_decode", "tl_control_tenure")]
    sources += [ROOT / "scripts" / n for n in
                ("map_tl_control_partition.tcl", "equiv_tl_control_partition.tcl",
                 "sta_tl_control_partition.tcl", "credit_abc.constr", "check_sta_report.py")]
    sources += [Path(__file__).resolve()]
    result = {"complete": False, "source_commit": subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "sources": {str(p.relative_to(ROOT)): sha(p) for p in sources},
        "libraries": {c: {"path": str(p), "sha256": sha(p)} for c, p in libs.items()},
        "runs": [], "widths": [], "full_top_sta": False, "physical_signoff": False}
    for path in sources:
        snapshot = stage / "sources" / path.relative_to(ROOT)
        snapshot.parent.mkdir(parents=True, exist_ok=True)
        snapshot.write_bytes(path.read_bytes())

    def save():
        (stage / "results.json").write_text(json.dumps(result, indent=2) + "\n")

    def run(name, cmd, env=None, timeout=600):
        start = time.monotonic()
        with (stage / (name + ".log")).open("w") as log:
            try:
                status = subprocess.run(cmd, cwd=ROOT, env=os.environ | (env or {}),
                                        stdout=log, stderr=subprocess.STDOUT,
                                        timeout=timeout).returncode
            except subprocess.TimeoutExpired:
                status = 124
                log.write("\nFAIL runner timeout\n")
        row = {"name": name, "command": list(map(str, cmd)), "environment": env or {},
               "exit": status, "seconds": time.monotonic() - start}
        result["runs"].append(row)
        save()
        print(name, "exit", status, flush=True)
        return row

    save()
    run("yosys_version", ["yosys", "-V"])
    run("sta_version", [str(args.sta.resolve()), "-version"])
    for width in (8, 16):
        mapped = stage / f"width{width}"
        mapped.mkdir()
        env = {"UALINK_LIBERTY": str(libs["ssg0p81v125c"]),
               "UALINK_WIDTH": str(width), "UALINK_BUILD_DIR": str(mapped)}
        mapping = run(f"map_{width}", ["yosys", "-Q", "-T", "-c",
                      "scripts/map_tl_control_partition.tcl"], env)
        profile = {"width": width, "mapping_exit": mapping["exit"], "sta": []}
        result["widths"].append(profile)
        if mapping["exit"]:
            save()
            continue
        netlist = mapped / "mapped.v"
        profile["netlist_sha256"] = sha(netlist)
        env["UALINK_NETLIST"] = str(netlist)
        for corner in CORNERS:
            for period in ("0.640", "6.400"):
                name = f"sta_{width}_{corner}_{period}"
                timing = run(name, [str(args.sta.resolve()), "-exit",
                             "scripts/sta_tl_control_partition.tcl"],
                             env | {"UALINK_LIBERTY": str(libs[corner]),
                                    "UALINK_PERIOD_NS": period})
                report = (stage / (name + ".log")).read_text()
                row = {"corner": corner, "period_ns": float(period), "exit": timing["exit"]}
                for mode, key in (("max", "setup_slack_ns"), ("min", "hold_slack_ns")):
                    values = re.findall(rf"^worst slack {mode}\s+(\S+)\s*$", report, re.M)
                    row[key] = float(values[0]) if len(values) == 1 else None
                try:
                    check_report(report, design="control_partition")
                    row["report_gate"] = timing["exit"] == 0
                except ValueError as error:
                    row["report_gate"] = False
                    row["diagnostic"] = str(error)
                profile["sta"].append(row)
                save()
        proof = run(f"equiv_{width}", ["yosys", "-Q", "-T", "-c",
                    "scripts/equiv_tl_control_partition.tcl"], env, timeout=900)
        profile["equivalence_exit"] = proof["exit"]
        profile["netlist_unchanged"] = profile["netlist_sha256"] == sha(netlist)
        save()
    result["sources_unchanged"] = all(sha(ROOT / p) == h for p, h in result["sources"].items())
    result["complete"] = True
    result["all_gates_passed"] = result["sources_unchanged"] and len(result["widths"]) == 2 and all(
        p["mapping_exit"] == 0 and p.get("equivalence_exit") == 0 and p.get("netlist_unchanged")
        and len(p["sta"]) == 10 and all(r["report_gate"] for r in p["sta"])
        for p in result["widths"])
    save()
    print("measurement complete; all gates passed:", result["all_gates_passed"], flush=True)
    return 0 if result["all_gates_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

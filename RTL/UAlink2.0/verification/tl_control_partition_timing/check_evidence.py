"""Run: python3 verification/tl_control_partition_timing/check_evidence.py [--label mapped_baseline].

Outputs: evidence.json bound to actual source snapshots, netlists, libraries and logs.
Next: resolve measured timing/proof failures; a successful audit is not timing closure.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.check_sta_report import check_report


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", default="mapped_baseline")
    args = parser.parse_args()
    require(bool(re.fullmatch(r"[a-zA-Z0-9_-]+", args.label)), "invalid label")
    base = ROOT / "build/verification/tl_control_partition_timing" / args.label
    run = json.loads((base / "results.json").read_text())
    require(run["complete"] and run["sources_unchanged"], "incomplete or changed measurement")
    require(len(run["runs"]) == 26 and len({r["name"] for r in run["runs"]}) == 26,
            "tool/mapping/proof/timing run inventory")
    require(set(run["libraries"]) == {"tt0p9v25c", "ssg0p81v125c", "ssg0p81vm40c",
                                      "ffg0p99v125c", "ffg0p99vm40c"}, "corner inventory")
    for name, value in run["sources"].items():
        require(digest(ROOT / name) == value, "canonical source changed: " + name)
        require(digest(base / "sources" / name) == value, "snapshot changed: " + name)
    for corner, item in run["libraries"].items():
        require(digest(Path(item["path"])) == item["sha256"], "library changed: " + corner)
    rows = []
    require([p["width"] for p in run["widths"]] == [8, 16], "width matrix")
    for profile in run["widths"]:
        width = profile["width"]
        require(profile["mapping_exit"] == 0, "mapping failed")
        mapped = base / f"width{width}"
        require(digest(mapped / "mapped.v") == profile["netlist_sha256"], "netlist changed")
        graph = json.loads((mapped / "mapped.json").read_text())
        module = graph["modules"]["tl_control_partition"]
        require(len(module["ports"]["i_capacity"]["bits"]) == 20 * (width + 1), "parameter mismatch")
        cells = module["cells"]
        require(all(not c["type"].startswith("$") and c["type"] in graph["modules"]
                    for c in cells.values()), "unmapped or unresolved cell")
        ff = [c for c in cells.values() if "CP" in c["connections"]]
        require(len(ff) == 4 and all(c["type"] == "DFQD2BWP40P140" for c in ff), "unexpected storage")
        require(all(c["connections"]["CP"] == module["ports"]["i_clk"]["bits"] for c in ff),
                "derived clock in mapped storage")
        ff_instances = re.findall(r"\bDFQD2BWP40P140\s+\S+\s*\((.*?)\);",
                                  (mapped / "mapped.v").read_text(), re.S)
        require(len(ff_instances) == 4 and all(re.search(r"\.CP\(i_clk\)", body)
                                               for body in ff_instances), "actual Verilog clock differs")
        require({b for c in ff for b in c["connections"]["Q"]}
                == set(module["netnames"]["r_cursor"]["bits"]), "state differs from real cursor")
        area = json.loads((mapped / "area.json").read_text())["modules"]["\\tl_control_partition"]
        require(area["num_cells"] == len(cells), "area/netlist cell mismatch")
        expected = {(c, p) for c in run["libraries"] for p in (0.64, 6.4)}
        require(len(profile["sta"]) == 10 and {(r["corner"], r["period_ns"])
                for r in profile["sta"]} == expected, "STA matrix incomplete")
        paths = []
        for row in profile["sta"]:
            name = f"sta_{width}_{row['corner']}_{row['period_ns']:.3f}"
            record = [r for r in run["runs"] if r["name"] == name]
            require(len(record) == 1 and record[0]["exit"] == row["exit"], "STA exit provenance")
            require(record[0]["environment"]["UALINK_NETLIST"] == str(mapped / "mapped.v"), "wrong netlist")
            require(float(record[0]["environment"]["UALINK_PERIOD_NS"]) == row["period_ns"]
                    and int(record[0]["environment"]["UALINK_WIDTH"]) == width, "wrong period/width")
            require(record[0]["environment"]["UALINK_LIBERTY"] == run["libraries"][row["corner"]]["path"],
                    "wrong corner")
            report = (base / (name + ".log")).read_text()
            blocks = re.split(r"(?=^Startpoint:)", report, flags=re.M)
            maximum = next((b for b in blocks if "Path Type: max" in b), None)
            require(maximum is not None, "missing actual maximum path")
            paths.append({"corner": row["corner"], "period_ns": row["period_ns"],
                          "endpoints": re.findall(r"^(?:Startpoint|Endpoint):.*$", maximum, re.M),
                          "cell_pin_rows": len(re.findall(r"\([^\n]*BWP40P140\)", maximum))})
            for mode, key in (("max", "setup_slack_ns"), ("min", "hold_slack_ns")):
                values = re.findall(rf"^worst slack {mode}\s+(\S+)\s*$", report, re.M)
                require(len(values) == 1 and math.isfinite(float(values[0]))
                        and float(values[0]) == row[key], "incomplete/incorrect slack")
            try:
                check_report(report, design="control_partition")
                passed = row["exit"] == 0
            except ValueError:
                passed = False
            require(passed == row["report_gate"], "report gate mismatch")
        proof = (base / f"equiv_{width}.log").read_text()
        proof_closed = profile["equivalence_exit"] == 0
        if proof_closed:
            require("SAT proof finished - no model found: SUCCESS!" in proof
                    and "Induction step proven: SUCCESS!" in proof, "missing actual proof completion")
        rows.append({"width": width, "mapped_cells": len(cells), "cell_area_um2": area["area"],
                     "ff_bits": len(ff), "raw_clock": True, "equivalence_closed": proof_closed,
                     "equivalence_exit": profile["equivalence_exit"], "timing": profile["sta"],
                     "maximum_paths": paths})
    result = {"audit_complete": True, "widths": rows, "actual_sta_runs": 20,
              "passed_sta_runs": sum(r["report_gate"] for p in rows for r in p["timing"]),
              "all_timing_closed": all(r["report_gate"] for p in rows for r in p["timing"]),
              "full_top_sta": False, "wire_parasitics": False, "physical_signoff": False,
              "full_goal_complete": False}
    (base / "evidence.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

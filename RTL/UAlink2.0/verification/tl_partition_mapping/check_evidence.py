"""Run: python3 [-O] verification/tl_partition_mapping/check_evidence.py.
Writes build/verification/tl_partition_mapping/evidence.json for the reset stage.
Next: discharge post-reset induction and every original output before claiming
mapped equivalence. A successful audit here is explicitly a partial-stage audit.
"""
from pathlib import Path
import hashlib
import json
import re

from run import check_inventory, check_outputs

ROOT = Path(__file__).resolve().parents[2]
STAGE = ROOT / "build/verification/tl_partition_mapping"


def need(condition, message):
    if not condition:
        raise ValueError(message)


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit_run(label, fault):
    folder = STAGE / label
    result = read(folder / "results.json")
    need(result["complete"] and result["scope"] == "reset", "incomplete or wrong proof scope")
    need(result["fault"] == fault and result["requested_widths"] == [8, 16], "wrong fault/width matrix")
    need(not result["mapped_equivalence_closed"], "reset cannot close mapping equivalence")
    need(result["all_passed"] == (fault is None), "unexpected aggregate result")
    need(result["runner_sha256"] == sha(folder / "runner.py"), "changed executed runner snapshot")
    for name, digest in result["sources"].items():
        need(sha(ROOT / name) == digest, "changed mapped source: " + name)
    need(sha(Path(result["library"]["path"])) == result["library"]["sha256"], "changed actual Liberty")
    need([r["width"] for r in result["results"]] == [8, 16], "missing/duplicate width")
    for row in result["results"]:
        unit = folder / f"width{row['width']}"
        healthy = ROOT / f"build/verification/tl_control_partition_timing/static_reduction/width{row['width']}/mapped.v"
        need(sha(healthy) == row["healthy_netlist_sha256"], "changed healthy mapped input")
        need(sha(unit / "mapped.v") == row["netlist_sha256"], "changed tested mapped input")
        old = healthy.read_text()
        new = (unit / "mapped.v").read_text()
        if fault is None:
            need(old == new, "healthy proof did not use the actual mapped netlist")
        else:
            pattern = r"DFQD2BWP40P140\s+\S+\s*\(\s*\.CP\(i_clk\),\s*\.D\([^()]+\),\s*\.Q\(r_cursor\[0\]\)\s*\);"
            cells = re.findall(pattern, old)
            need(len(cells) == 1, "fault target is not one actual mapped flip-flop")
            replacement = cells[0].replace(".CP(i_clk)", ".CP(1'b0)") if fault == "clock" else re.sub(r"\.D\([^()]+\)", ".D(i_source_valid)", cells[0])
            need(old.replace(cells[0], replacement, 1) == new, "mutation changed more than its declared connection")
        need(row["prepare_exit"] == 0, "netlist failed elaboration")
        graph = read(unit / "prepared.json")["modules"]["partition_miter"]
        need(row["output_coverage"] == check_outputs(graph), "original output inventory changed")
        if fault == "clock":
            try:
                check_inventory(graph)
            except ValueError as error:
                need(row.get("inventory_error") == str(error), "unexpected inventory error")
            else:
                raise ValueError("wrong real mapped clock was accepted")
            need(row["queries"] == [], "clock-invalid graph reached SAT")
            continue
        need(row["inventory"] == check_inventory(graph), "state/clock inventory changed")
        need(len(row["queries"]) == 1, "missing/extra reset proof")
        query = row["queries"][0]
        script = (unit / "reset_zero.ys").read_text()
        commands = re.findall(r"^sat .*", script, re.M)
        expected = f"sat -verify -timeout 90 -seq 2 -set-at 1 in_i_rstn 0 -prove-skip 1 -prove gate_r_cursor 0 -prove gold_r_cursor 0 -dump_json {unit}/reset_zero_counterexample.json partition_miter"
        need(commands == [expected], "reset query weakened or changed")
        need("-set-init" not in script and "-ignore" not in script and "-input" not in script,
             "reset proof must start with arbitrary actual state and intact drivers")
        log = (unit / "reset_zero.log").read_text()
        if fault is None:
            need(query["exit"] == 0 and query["passed"] and log.count("SAT proof finished - no model found: SUCCESS!") == 1,
                 "actual reset proof did not pass")
        else:
            need(query["exit"] == 1 and not query["passed"] and "proof did fail" in log,
                 "reset fault did not produce an actual SAT mismatch")
            need((unit / "reset_zero_counterexample.json").is_file(), "missing actual SAT witness")
    return [row["width"] for row in result["results"]]


def main():
    widths = audit_run("reset_verified", None)
    audit_run("reset_bypass", "reset")
    audit_run("clock_mutation", "clock")
    result = {"audit_passed": True, "scope": "actual mapped reset and clock prerequisite only",
              "reset_proved_widths": widths, "actual_reset_faults_detected": 2,
              "actual_clock_faults_rejected": 2, "state_bits_per_design": 4,
              "original_output_ports_observed": 10, "original_output_bits_observed": 529,
              "post_reset_induction_proved": False, "all_original_outputs_proved": False,
              "mapped_equivalence_closed": False, "full_top_sta": False, "full_goal_complete": False}
    (STAGE / "evidence.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

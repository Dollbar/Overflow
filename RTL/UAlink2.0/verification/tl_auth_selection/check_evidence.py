"""Run: python3 [-O] verification/tl_auth_selection/check_evidence.py.
Writes audited evidence.json under build/verification/tl_auth_selection after
checking actual RTL/mapped proofs, peers, faults and unchanged process budgets.
Next close the remaining combinational paths and complete the integrated IP goal.
"""
from pathlib import Path
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "verification/tl_partition_mapping"))
from run_cec import inspect_graph, named_blif, need, sha
from scripts.check_sta_report import check_report

STAGE = ROOT / "build/verification/tl_auth_selection"
PROOFS = ROOT / "build/verification/tl_prefix_cost"
PEERS = ROOT / "build/verification/tl_control_partition"
REFERENCE = "9994f2d0491e8ae444c88146d1e6e82889afb7af"


def read(path):
    return json.loads(path.read_text())


def identity(result):
    for name, digest in result["sources"].items():
        need(sha(ROOT / name) == digest, "changed compiled input: " + name)


def proof(label, widths, digest):
    base = PROOFS / label
    result = read(base / "results.json")
    need(result["complete"] and result["all_passed"] and result["widths"] == widths and
         [r["width"] for r in result["results"]] == widths, "incomplete proof matrix")
    need(result["reference"] == REFERENCE and result["candidate_sha256"] == digest == sha(base / "candidate.v"), "wrong comparison source")
    need((base / "original.v").read_bytes() == subprocess.check_output(["git", "show", REFERENCE + ":rtl/tl/tl_control_partition.v"], cwd=ROOT), "wrong reference RTL")
    need(sha(base / "runner.py") == result["runner_sha256"] and sha(base / "cec_support.py") == result["support_sha256"], "changed proof implementation")
    need(result["original_output_bits"] == 529 and result["next_state_bits"] == 4 and not result["protocol_assumptions"], "weakened proof denominator")
    for name, dep_sha in result["dependencies"].items():
        need(sha(base / name) == dep_sha == sha(ROOT / "rtl/tl" / name), "changed dependency")
        gold = base / "reference_dependencies" / name
        need(gold.read_bytes() == subprocess.check_output(["git", "show", REFERENCE + ":rtl/tl/" + name], cwd=ROOT) and
             sha(gold) == result["reference_dependencies"][name], "reference dependency drift")
    for row in result["results"]:
        folder = base / f"width{row['width']}"
        log = (folder / "cec.log").read_text()
        need(row["passed"] and row["prepare"]["exit"] == row["cec"]["exit"] == 0 and log.count("Networks are equivalent.") == 1 and
             not re.search(r"Warning:|Error:|ERROR:", log), "actual CEC did not pass cleanly")
        need((folder / "cec_command.txt").read_text() == f'cec -T 120 -v "{folder}/gold_named.blif" "{folder}/gate_named.blif"\n', "changed CEC command")
        for side in ("gold", "gate"):
            text, inventory = named_blif((folder / f"{side}.blif").read_text(), read(folder / f"{side}.json")["modules"][side], row["width"])
            need(text == (folder / f"{side}_named.blif").read_text() and inventory == read(folder / f"{side}_naming.json"), "changed state/clock/active-logic/output correspondence")
        if result["mode"] == "mapped":
            need(sha(folder / "mapped.v") == row["netlist_sha256"] == sha(PROOFS / f"auth_shared_shift_timing/width{row['width']}/mapped.v"), "mapped proof and STA used different netlists")


def main():
    digest = sha(STAGE / "shared_shift/tl_control_partition.v")
    need(digest == sha(ROOT / "rtl/tl/tl_control_partition.v"), "candidate not adopted exactly")
    for label, widths in (("auth_shared_shift", [8, 16]), ("auth_shift_low", [9, 10, 11]),
                          ("auth_shift_middle", [12, 13, 14]), ("auth_shift_high", [15]), ("auth_shift_mapped", [8, 16])):
        proof(label, widths, digest)
    unit = read(PEERS / "auth_shared_shift/results.json")
    identity(unit)
    need(unit["complete"] and [r["width"] for r in unit["results"]] == [8, 16] and all(r["compile_exit"] == r["run_exit"] == 0 and r["vectors"] == 2428 for r in unit["results"]), "unit vectors incomplete")
    traces = 0
    for current, baseline in (("auth_shift_peers", "select_tenure_peers"), ("auth_shift_minimum", "select_tenure_minimum")):
        result = read(PEERS / current / "results.json")
        identity(result)
        need(result["complete"] and len(result["results"]) == 16 and all(r["passed"] for r in result["results"]), "actual peers incomplete")
        for folder in sorted((PEERS / current).glob("w*_a*_s*_l*")):
            for name in ("trace.txt", "queue_trace.txt", "partition_trace.txt"):
                need((folder / name).read_bytes() == (PEERS / baseline / folder.name / name).read_bytes(), "actual cycle trace changed")
                traces += 1
    need(traces == 96 and read(PEERS / "auth_shift_evidence.json")["actual_configs"] == 32, "trace audit scope changed")
    checks = read(PEERS / "auth_shift_checks/results.json")
    identity(checks)
    need(checks["complete"] and all(r["passed"] for r in checks["results"]) and checks["boundary_fault"] == "truncated_header", "functional fault matrix incomplete")
    need({k: sum(r["kind"] == k for r in checks["results"]) for k in ("lint", "synthesis", "unit_fault", "peer_fault")} ==
         {"lint": 2, "synthesis": 2, "unit_fault": 8, "peer_fault": 56}, "fault denominator changed")
    tag_mutant = (PEERS / "auth_shift_checks/lost_tag_offset/tl_control_partition.v").read_text()
    need("assign tags_shifted=i_source_tags[255:0];" in tag_mutant, "tag fault did not modify real shared offset")
    for row in checks["results"]:
        if row["kind"] == "unit_fault":
            fault = read(PEERS / ("auth_shift_checks_fault_" + row["name"]) / "results.json")
            identity(fault)
            need(len(fault["results"]) == 2 and all(r["compile_exit"] == 0 and r["run_exit"] == 1 for r in fault["results"]), "fault was not compiled RTL mismatch")
        elif row["kind"] == "peer_fault":
            log = (PEERS / "auth_shift_checks" / (row["name"] + "_" + row["config"] + ".log")).read_text()
            need("FATAL:" in log and "PASS actual channels" not in log, "actual peer fault accepted")
    faults = read(PROOFS / "auth_shift_mapped_faults/results.json")
    need(faults["complete"] and faults["all_passed"] and faults["candidate_sha256"] == digest and
         {(r["width"], r["fault"]) for r in faults["results"]} == {(w, f) for w in (8, 16) for f in ("healthy_reset", "clock", "transition", "tags")}, "mapped reset/fault matrix incomplete")
    for row in faults["results"]:
        folder = PROOFS / "auth_shift_mapped_faults" / f"{row['fault']}{row['width']}"
        need(sha(folder / "mapped.v") == row["netlist_sha256"] and row["passed"], "changed mapped mutant")
        if row["fault"] == "clock":
            try:
                inspect_graph(read(folder / "gate.json")["modules"]["gate"], row["width"])
            except ValueError as error:
                need(str(error) == row["inventory_error"], "changed clock rejection")
            else:
                raise ValueError("actual wrong clock accepted")
        else:
            if row["fault"] != "healthy_reset":
                need(row["cec"]["exit"] == 0 and "Networks are NOT EQUIVALENT." in (folder / "cec.log").read_text(), "mapped fault accepted")
            for name in ("reset", "transition", "tags"):
                if name in row:
                    healthy = row["fault"] == "healthy_reset"
                    need(row[name]["exit"] == (0 if healthy else 1) and
                         ("SAT proof finished - no model found: SUCCESS!" if healthy else "proof did fail") in (folder / (name + ".log")).read_text(), "wrong mapped SAT result")
                    if not healthy:
                        need((folder / (name + "_counterexample.json")).is_file(), "missing mapped counterexample")
    timing = read(PROOFS / "auth_shared_shift_timing/results.json")
    identity(timing)
    baseline = read(PROOFS / "select_tenure_clean_timing/results.json")
    need(timing["complete"] and timing["sources_unchanged"] and timing["candidate_sha256"] == digest and timing["libraries"] == baseline["libraries"], "changed actual process inputs")
    for library in timing["libraries"].values():
        need(sha(Path(library["path"])) == library["sha256"], "changed process corner")
    need([r["width"] for r in timing["widths"]] == [8, 16], "missing measured width")
    physical = []
    for row in timing["widths"]:
        folder = PROOFS / f"auth_shared_shift_timing/width{row['width']}"
        need(row["mapping"]["exit"] == 0 and sha(folder / "mapped.v") == row["netlist_sha256"], "mapping changed")
        need(len(row["sta"]) == 10 and {(s["corner"], s["period_ns"]) for s in row["sta"]} == {(c, p) for c in timing["libraries"] for p in (0.640, 6.400)}, "STA matrix changed")
        for sta in row["sta"]:
            log = (folder / f"{sta['corner']}_{sta['period_ns']:.3f}.log").read_text()
            if sta["period_ns"] == 6.4:
                check_report(log, design="control_partition")
                need(sta["exit"] == 0 and sta["report_gate"], "reference STA failed")
            else:
                need(sta["exit"] == 1 and sta["setup_slack_ns"] < 0 and "Negative setup or hold slack" in log, "main failure was not actual STA")
        area = read(folder / "area.json")["design"]
        physical.append({"width": row["width"], "cells": area["num_cells"], "area_um2": area["area"],
                         "worst_setup_ns": min(s["setup_slack_ns"] for s in row["sta"]),
                         "worst_reference_setup_ns": min(s["setup_slack_ns"] for s in row["sta"] if s["period_ns"] == 6.4)})
    skill = read(STAGE / "skill_gate.json")
    need(skill["ok"] and skill["errors"] == 0, "artifact gate failed")
    compatibility = read(STAGE / "compatibility.json")
    need(compatibility["exit"] == 0 and compatibility["rtl_sha256"] == digest, "clean export compatibility failed")
    for source in (*sorted((ROOT / "rtl").rglob("*.v")), ROOT / "Makefile"):
        need(source.read_bytes() == (STAGE / "clean_export" / source.relative_to(ROOT)).read_bytes(), "adopted source differs from tested export")
    result = {"complete": True, "rtl_equivalence_widths": list(range(8, 17)), "mapped_equivalence_widths": [8, 16],
              "unit_vectors": 4856, "actual_peer_configs": 32, "identical_trace_files": traces, "unit_faults": 16, "peer_faults": 56,
              "mapped_reset_proofs": 2, "mapped_sat_counterexamples": 6, "mapped_clock_rejections": 2,
              "physical": physical, "reference_sta_passed": 10, "main_sta_passed": 0,
              "artifact_errors": 0, "artifact_advisories": skill["warnings"], "compatibility_exit": 0,
              "main_frequency_closed": False, "full_top_sta": False, "full_goal_complete": False}
    (STAGE / "evidence.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

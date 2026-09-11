"""Run: python3 [-O] verification/tl_prefix_cost/check_evidence.py.
Writes evidence.json after checking adopted RTL, original/mapped equivalence,
actual vectors/peers/faults and unchanged-budget process timing. Next close main
frequency and the remaining complete IP requirements; this is only one block.
"""
from pathlib import Path
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "verification/tl_partition_mapping"))
from scripts.check_sta_report import check_report
from run_cec import inspect_graph, named_blif, need, sha

BASE = ROOT / "build/verification/tl_prefix_cost"
PEERS = ROOT / "build/verification/tl_control_partition"


def read(path):
    return json.loads(path.read_text())


def identity(result):
    for name, digest in result["sources"].items():
        need(sha(ROOT / name) == digest, "compiled source changed: " + name)


def proof(label, expected_widths, candidate_digest):
    folder = BASE / label
    result = read(folder / "results.json")
    need(result["complete"] and result["all_passed"] and result["widths"] == expected_widths, "incomplete proof matrix")
    need(result["candidate_sha256"] == candidate_digest and sha(folder / "candidate.v") == candidate_digest, "wrong proof candidate")
    original = subprocess.check_output(["git", "show", result["reference"] + ":rtl/tl/tl_control_partition.v"], cwd=ROOT)
    need((folder / "original.v").read_bytes() == original and sha(folder / "original.v") == result["original_sha256"], "wrong original RTL")
    need(sha(folder / "runner.py") == result["runner_sha256"] and sha(folder / "cec_support.py") == result["support_sha256"], "changed proof implementation snapshot")
    for name, digest in result["dependencies"].items():
        need(sha(folder / name) == digest == sha(ROOT / "rtl/tl" / name), "changed shared dependency")
    need(result["original_output_bits"] == 529 and result["next_state_bits"] == 4 and not result["protocol_assumptions"], "wrong proof denominator or assumptions")
    need([r["width"] for r in result["results"]] == expected_widths, "missing/duplicate proof width")
    if result["mode"] == "mapped":
        need(sha(Path(result["library"]["path"])) == result["library"]["sha256"], "changed actual functional Liberty")
    for row in result["results"]:
        unit = folder / f"width{row['width']}"
        need(row["prepare"]["exit"] == row["cec"]["exit"] == 0 and row["passed"], "proof tool did not pass")
        log = (unit / "cec.log").read_text()
        need(log.count("Networks are equivalent.") == 1 and not re.search(r"Warning:|Error:|ERROR:", log), "CEC not closed cleanly")
        command = f'cec -T 120 -v "{unit}/gold_named.blif" "{unit}/gate_named.blif"\n'
        need((unit / "cec_command.txt").read_text() == command, "CEC matching or scope changed")
        for side in ("gold", "gate"):
            graph = read(unit / f"{side}.json")["modules"][side]
            text, inventory = named_blif((unit / f"{side}.blif").read_text(), graph, row["width"])
            need(text == (unit / f"{side}_named.blif").read_text() and inventory == read(unit / f"{side}_naming.json"), "changed state/clock/output correspondence")
        if result["mode"] == "mapped":
            need(sha(unit / "mapped.v") == row["netlist_sha256"] == sha(BASE / f"candidate_timing/width{row['width']}/mapped.v"), "proof and STA used different netlists")
    return result


def main():
    candidate = BASE / "shared_clean/tl_control_partition.v"
    digest = sha(candidate)
    need(digest == sha(ROOT / "rtl/tl/tl_control_partition.v"), "candidate has not been adopted exactly")
    for label, widths in (("rtl_low", [8, 9, 10]), ("rtl_middle", [11, 12, 13]), ("rtl_high", [14, 15, 16]), ("mapped_equivalence", [8, 16])):
        proof(label, widths, digest)
    removal = BASE / "boundary_guard_removal"
    removal_digest = sha(removal / "candidate.v")
    proof("boundary_guard_removal", [8, 16], removal_digest)
    need((removal / "candidate.v").read_text() == candidate.read_text().replace("&&complete_boundary&&", "&&1'b1&&"), "unexplained equivalent mutation")
    unit = read(PEERS / "shared_cost_clean/results.json")
    identity(unit)
    need(unit["complete"] and [r["width"] for r in unit["results"]] == [8, 16], "incomplete independent vectors")
    need(all(r["compile_exit"] == r["run_exit"] == 0 and r["vectors"] == 2428 for r in unit["results"]), "unit vector denominator changed")
    traces = 0
    for current, original in (("shared_cost_peers", "reduction_peers"), ("shared_cost_minimum", "reduction_minimum")):
        result = read(PEERS / current / "results.json")
        identity(result)
        need(result["complete"] and len(result["results"]) == 16, "incomplete actual peer matrix")
        for directory in sorted((PEERS / current).glob("w*_a*_s*_l*")):
            for name in ("trace.txt", "queue_trace.txt", "partition_trace.txt"):
                need((directory / name).read_bytes() == (PEERS / original / directory.name / name).read_bytes(), "changed actual cycle trace")
                traces += 1
    need(traces == 96, "trace comparison denominator changed")
    peer_audit = read(PEERS / "shared_cost_evidence.json")
    need(peer_audit["scope"] == "actual_peer_traces_only", "wrong independent trace audit")
    checks = read(PEERS / "shared_cost_checks_closed/results.json")
    identity(checks)
    need(checks["complete"] and checks["boundary_fault"] == "truncated_header" and all(r["passed"] for r in checks["results"]), "actual lint/synthesis/fault matrix failed")
    need({kind: sum(r["kind"] == kind for r in checks["results"]) for kind in ("lint", "synthesis", "unit_fault", "peer_fault")} ==
         {"lint": 2, "synthesis": 2, "unit_fault": 8, "peer_fault": 56}, "fault denominator changed")
    for row in checks["results"]:
        if row["kind"] == "unit_fault":
            r = read(PEERS / ("shared_cost_checks_closed_fault_" + row["name"]) / "results.json")
            need(len(r["results"]) == 2 and all(v["compile_exit"] == 0 and v["run_exit"] == 1 for v in r["results"]), "unit fault was not actual compiled RTL mismatch")
    faults = read(BASE / "mapped_faults/results.json")
    need(faults["complete"] and faults["all_passed"] and faults["candidate_sha256"] == digest and
         {(r["width"], r["fault"]) for r in faults["results"]} == {(w, f) for w in (8, 16) for f in ("healthy_reset", "clock", "transition", "tags")}, "mapped fault/reset matrix incomplete")
    for row in faults["results"]:
        folder = BASE / "mapped_faults" / f"{row['fault']}{row['width']}"
        need(row["passed"] and sha(folder / "mapped.v") == row["netlist_sha256"], "mapped fault artifact changed")
        if row["fault"] == "clock":
            need(row["prepare"]["exit"] == 0, "clock fault did not elaborate")
            try:
                inspect_graph(read(folder / "gate.json")["modules"]["gate"], row["width"])
            except ValueError as error:
                need(str(error) == row["inventory_error"], "unexpected clock rejection")
            else:
                raise ValueError("wrong actual mapped clock was accepted")
        else:
            if row["fault"] != "healthy_reset":
                need(row["cec"]["exit"] == 0 and "Networks are NOT EQUIVALENT." in (folder / "cec.log").read_text(), "mapped fault not rejected by CEC")
            for name in ("reset", "transition", "tags"):
                if name not in row:
                    continue
                expected_pass = row["fault"] == "healthy_reset"
                log = (folder / (name + ".log")).read_text()
                need(row[name]["exit"] == (0 if expected_pass else 1) and
                     ("SAT proof finished - no model found: SUCCESS!" if expected_pass else "proof did fail") in log, "wrong actual SAT result")
                if not expected_pass:
                    need((folder / (name + "_counterexample.json")).is_file(), "missing concrete SAT counterexample")
    timing = read(BASE / "candidate_timing/results.json")
    need(timing["complete"] and timing["candidate_sha256"] == digest and [r["width"] for r in timing["widths"]] == [8, 16], "incomplete process measurement")
    old = read(ROOT / "build/verification/tl_control_partition_timing/static_reduction/results.json")
    for lib in old["libraries"].values():
        need(sha(Path(lib["path"])) == lib["sha256"], "changed process corner")
    reproduced = read(BASE / "timing_reproduced/results.json")
    identity(reproduced)
    need(reproduced["complete"] and reproduced["sources_unchanged"] and
         reproduced["candidate_sha256"] == digest and not reproduced["all_sta_passed"], "incomplete timing reproduction")
    need((BASE / "timing_reproduced/runner.py").read_bytes() ==
         (ROOT / "verification/tl_prefix_cost/run_timing.py").read_bytes(), "timing runner changed after measurement")
    need(reproduced["libraries"] == old["libraries"] and
         [r["width"] for r in reproduced["widths"]] == [8, 16], "reproduced process inputs changed")
    physical, passed = [], 0
    for row in timing["widths"]:
        folder = BASE / f"candidate_timing/width{row['width']}"
        need(row["mapping"]["exit"] == 0 and sha(folder / "mapped.v") == row["netlist_sha256"], "mapping incomplete or modified")
        repeat = next(r for r in reproduced["widths"] if r["width"] == row["width"])
        repeated_folder = BASE / f"timing_reproduced/width{row['width']}"
        need(repeat["mapping"]["exit"] == 0 and repeat["netlist_sha256"] == row["netlist_sha256"] ==
             sha(repeated_folder / "mapped.v"), "reproduced mapped netlist differs")
        need(len(repeat["sta"]) == 10 and
             [(r["corner"], r["period_ns"], r["exit"], r["setup_slack_ns"]) for r in repeat["sta"]] ==
             [(r["corner"], r["period_ns"], r["exit"], r["setup_slack_ns"]) for r in row["sta"]], "reproduced STA differs")
        for sta in repeat["sta"]:
            if sta["period_ns"] == 6.400:
                check_report((repeated_folder / f"{sta['corner']}_{sta['period_ns']:.3f}.log").read_text(), design="control_partition")
                need(sta["report_gate"], "reproduced reference report gate failed")
        need({(s["corner"], s["period_ns"]) for s in row["sta"]} == {(c, p) for c in old["libraries"] for p in (0.640, 6.400)} and len(row["sta"]) == 10, "corner/period matrix changed")
        for sta in row["sta"]:
            log = (folder / f"{sta['corner']}_{sta['period_ns']:.3f}.log").read_text()
            if sta["period_ns"] == 6.400:
                check_report(log, design="control_partition")
                need(sta["exit"] == 0, "reference period did not pass")
                passed += 1
            else:
                need(sta["exit"] == 1 and sta["setup_slack_ns"] < 0 and "Negative setup or hold slack" in log, "main period failure was not actual timing")
        area = read(folder / "area.json")["design"]
        physical.append({"width": row["width"], "cells": area["num_cells"], "area_um2": area["area"],
                         "worst_setup_ns": min(r["setup_slack_ns"] for r in row["sta"]),
                         "worst_reference_setup_ns": min(r["setup_slack_ns"] for r in row["sta"] if r["period_ns"] == 6.4)})
    skill = read(BASE / "skill_gate.json")
    need(skill["ok"] and skill["errors"] == 0, "authored RTL artifact gate failed")
    invalid = read(BASE / "invalid_widths.json")
    need([r["width"] for r in invalid] == [7, 17] and all(r["rejected"] for r in invalid), "invalid widths not rejected")
    compatibility = read(BASE / "compatibility.json")
    need(compatibility["exit"] == 0 and compatibility["rtl_sha256"] == digest, "clean export compatibility not passed")
    for source in (*sorted((ROOT / "rtl").rglob("*.v")), ROOT / "Makefile"):
        need(source.read_bytes() == (BASE / "clean_export" / source.relative_to(ROOT)).read_bytes(), "current RTL/Makefile differs from tested export")
    result = {"complete": True, "rtl_equivalence_widths": list(range(8, 17)), "mapped_equivalence_widths": [8, 16],
              "original_output_bits": 529, "next_state_bits": 4, "unit_vectors": 4856, "actual_peer_configs": 32,
              "identical_trace_files": traces, "unit_faults": 16, "peer_faults": 56,
              "equivalent_guard_removal_widths": [8, 16], "mapped_mutant_netlists": 6,
              "mapped_sat_counterexamples": 6, "mapped_clock_rejections": 2, "actual_reset_proofs": 2,
              "physical": physical, "reference_sta_passed": passed, "main_sta_passed": 0,
              "reproduced_identical_netlists": 2, "reproduced_sta_runs": 20,
              "artifact_errors": 0, "artifact_advisories": skill["warnings"], "compatibility_exit": 0, "full_top_sta": False,
              "main_frequency_closed": False, "full_goal_complete": False}
    (BASE / "evidence.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

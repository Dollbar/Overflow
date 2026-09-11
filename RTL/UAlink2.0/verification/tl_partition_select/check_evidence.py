"""Run: python3 [-O] verification/tl_partition_select/check_evidence.py.
Audits the adopted parallel-tenure candidate and retained rejected selectors.
Writes evidence.json under build/verification/tl_partition_select. Next close
main-frequency and full integrated Endpoint/Switch requirements.
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

STAGE = ROOT / "build/verification/tl_partition_select"
PROOFS = ROOT / "build/verification/tl_prefix_cost"
PEERS = ROOT / "build/verification/tl_control_partition"
REFERENCE = "e34ea20a9c44df326f97c7da6d0e75bac5d49afe"


def read(path):
    return json.loads(path.read_text())


def reference(name):
    return subprocess.check_output(["git", "show", REFERENCE + ":rtl/tl/" + name], cwd=ROOT)


def identity(result):
    for name, digest in result["sources"].items():
        need(sha(ROOT / name) == digest, "changed actual tool input: " + name)


def check_proof(label, widths, digest):
    base = PROOFS / label
    result = read(base / "results.json")
    need(result["complete"] and result["all_passed"] and result["widths"] == widths and
         [r["width"] for r in result["results"]] == widths, "incomplete proof matrix")
    need(result["reference"] == REFERENCE and (base / "original.v").read_bytes() == reference("tl_control_partition.v"), "wrong reference")
    need(sha(base / "candidate.v") == result["candidate_sha256"] == digest, "wrong candidate")
    need(sha(base / "runner.py") == result["runner_sha256"] and sha(base / "cec_support.py") == result["support_sha256"], "changed proof runner")
    need(result["original_output_bits"] == 529 and result["next_state_bits"] == 4 and not result["protocol_assumptions"], "weakened proof scope")
    for name, dep_sha in result["dependencies"].items():
        need(sha(base / name) == dep_sha == sha(ROOT / "rtl/tl" / name), "changed gate dependency")
        gold = base / "reference_dependencies" / name
        need(gold.read_bytes() == reference(name) and sha(gold) == result["reference_dependencies"][name], "wrong gold dependency")
    for row in result["results"]:
        folder = base / f"width{row['width']}"
        log = (folder / "cec.log").read_text()
        need(row["prepare"]["exit"] == row["cec"]["exit"] == 0 and row["passed"] and
             log.count("Networks are equivalent.") == 1 and not re.search(r"Warning:|Error:|ERROR:", log), "CEC did not pass cleanly")
        need((folder / "cec_command.txt").read_text() == f'cec -T 120 -v "{folder}/gold_named.blif" "{folder}/gate_named.blif"\n', "changed comparison command")
        for side in ("gold", "gate"):
            graph = read(folder / f"{side}.json")["modules"][side]
            text, inventory = named_blif((folder / f"{side}.blif").read_text(), graph, row["width"])
            need(text == (folder / f"{side}_named.blif").read_text() and inventory == read(folder / f"{side}_naming.json"), "changed actual state/clock/logic/output inventory")
        if result["mode"] == "mapped":
            need(sha(folder / "mapped.v") == row["netlist_sha256"] == sha(PROOFS / f"select_tenure_clean_timing/width{row['width']}/mapped.v"), "proved netlist differs from measured netlist")


def main():
    digest = sha(STAGE / "tenure_clean/tl_control_partition.v")
    for name in ("tl_control_partition.v", "tl_control_tenure.v"):
        need((ROOT / "rtl/tl" / name).read_bytes() == (STAGE / "tenure_clean" / name).read_bytes(), "candidate not adopted exactly")
    for label, widths in (("select_tenure_low", [8, 9, 10]), ("select_tenure_middle", [11, 12, 13]),
                          ("select_tenure_high", [14, 15, 16]), ("select_tenure_mapped", [8, 16])):
        check_proof(label, widths, digest)
    contract = read(STAGE / "tenure_contract/results.json")
    need(contract["complete"] and contract["all_passed"] and contract["candidate_sha256"] == sha(ROOT / "rtl/tl/tl_control_tenure.v") and
         {(r["parallel"], r["fault"]) for r in contract["results"]} == {(p, f) for p in (False, True) for f in (False, True)}, "incomplete tenure contract")
    for row in contract["results"]:
        folder = STAGE / f"tenure_contract/parallel{int(row['parallel'])}_fault{int(row['fault'])}"
        log = (folder / "prove.log").read_text()
        need(sha(folder / "candidate.v") == row["source_sha256"] and row["passed"], "changed actual tenure fault")
        need(row["tool"]["exit"] == int(row["fault"]) and ("proof did fail" if row["fault"] else "SAT proof finished - no model found: SUCCESS!") in log, "wrong actual contract SAT result")
        if row["fault"]:
            need((folder / "counterexample.json").is_file(), "missing actual count fault counterexample")
    unit = read(PEERS / "select_tenure_clean/results.json")
    identity(unit)
    need(unit["complete"] and [r["width"] for r in unit["results"]] == [8, 16] and
         all(r["compile_exit"] == r["run_exit"] == 0 and r["vectors"] == 2428 for r in unit["results"]), "independent unit vectors incomplete")
    count = 0
    for new, old in (("select_tenure_peers", "shared_cost_peers"), ("select_tenure_minimum", "shared_cost_minimum")):
        peers = read(PEERS / new / "results.json")
        identity(peers)
        need(peers["complete"] and len(peers["results"]) == 16 and all(r["passed"] for r in peers["results"]), "actual peers incomplete")
        for folder in sorted((PEERS / new).glob("w*_a*_s*_l*")):
            for name in ("trace.txt", "queue_trace.txt", "partition_trace.txt"):
                need((folder / name).read_bytes() == (PEERS / old / folder.name / name).read_bytes(), "actual trace differs")
                count += 1
    need(count == 96 and read(PEERS / "select_tenure_evidence.json")["actual_configs"] == 32, "trace audit denominator changed")
    checks = read(PEERS / "select_tenure_checks/results.json")
    identity(checks)
    need(checks["complete"] and all(r["passed"] for r in checks["results"]) and checks["boundary_fault"] == "truncated_header", "functional fault gate failed")
    need({k: sum(r["kind"] == k for r in checks["results"]) for k in ("lint", "synthesis", "unit_fault", "peer_fault")} ==
         {"lint": 2, "synthesis": 2, "unit_fault": 8, "peer_fault": 56}, "functional fault denominator changed")
    for row in checks["results"]:
        if row["kind"] == "unit_fault":
            fault = read(PEERS / ("select_tenure_checks_fault_" + row["name"]) / "results.json")
            identity(fault)
            need(len(fault["results"]) == 2 and all(r["compile_exit"] == 0 and r["run_exit"] == 1 for r in fault["results"]), "unit fault was not an actual compiled mismatch")
        elif row["kind"] == "peer_fault":
            log = (PEERS / "select_tenure_checks" / (row["name"] + "_" + row["config"] + ".log")).read_text()
            need("FATAL:" in log and "PASS actual channels" not in log, "peer fault did not fail at runtime")
    faults = read(PROOFS / "select_tenure_mapped_faults/results.json")
    need(faults["complete"] and faults["all_passed"] and faults["candidate_sha256"] == digest and len(faults["results"]) == 8, "mapped reset/fault checks incomplete")
    for row in faults["results"]:
        folder = PROOFS / "select_tenure_mapped_faults" / f"{row['fault']}{row['width']}"
        need(sha(folder / "mapped.v") == row["netlist_sha256"] and row["passed"], "changed mapped fault")
        if row["fault"] == "clock":
            try:
                inspect_graph(read(folder / "gate.json")["modules"]["gate"], row["width"])
            except ValueError as error:
                need(str(error) == row["inventory_error"], "wrong clock rejection")
            else:
                raise ValueError("actual clock fault accepted")
        else:
            if row["fault"] != "healthy_reset":
                need(row["cec"]["exit"] == 0 and "Networks are NOT EQUIVALENT." in (folder / "cec.log").read_text(), "actual mapped fault accepted")
            for name in ("reset", "transition", "tags"):
                if name in row:
                    healthy = row["fault"] == "healthy_reset"
                    need(row[name]["exit"] == (0 if healthy else 1) and
                         ("SAT proof finished - no model found: SUCCESS!" if healthy else "proof did fail") in (folder / (name + ".log")).read_text(), "mapped SAT result changed")
                    if not healthy:
                        need((folder / (name + "_counterexample.json")).is_file(), "missing mapped SAT counterexample")
    physical = []
    libraries = read(PROOFS / "timing_reproduced/results.json")["libraries"]
    for label in ("select_parallel_timing", "select_sector_only_timing", "select_tenure_clean_timing"):
        base = PROOFS / label
        timing = read(base / "results.json")
        if label == "select_tenure_clean_timing":
            identity(timing)
            need(timing["candidate_sha256"] == digest, "wrong final timing candidate")
        else:
            for name, source_sha in timing["sources"].items():
                source = ROOT / name
                if source.parent == ROOT / "rtl/tl":
                    import hashlib
                    need(hashlib.sha256(reference(source.name)).hexdigest() == source_sha, "changed rejected baseline dependency")
                else:
                    need(sha(source) == source_sha, "changed measurement script")
            proof_base = PROOFS / label.removesuffix("_timing")
            rejected = read(proof_base / "results.json")
            need(rejected["complete"] and rejected["all_passed"] and rejected["widths"] == [8, 16] and
                 rejected["candidate_sha256"] == timing["candidate_sha256"] == sha(proof_base / "candidate.v"), "rejected selector was not proved before measurement")
            for proof_row in rejected["results"]:
                proof_folder = proof_base / f"width{proof_row['width']}"
                need(proof_row["passed"] and proof_row["prepare"]["exit"] == proof_row["cec"]["exit"] == 0 and
                     "Networks are equivalent." in (proof_folder / "cec.log").read_text(), "rejected selector proof incomplete")
        need(timing["complete"] and timing["sources_unchanged"] and timing["libraries"] == libraries and [r["width"] for r in timing["widths"]] == [8, 16], "changed process measurement scope")
        for lib in libraries.values():
            need(sha(Path(lib["path"])) == lib["sha256"], "changed process library")
        for row in timing["widths"]:
            folder = base / f"width{row['width']}"
            need(row["mapping"]["exit"] == 0 and sha(folder / "mapped.v") == row["netlist_sha256"], "mapping artifact changed")
            need(len(row["sta"]) == 10 and {(s["corner"], s["period_ns"]) for s in row["sta"]} == {(c, p) for c in libraries for p in (0.640, 6.400)}, "corner matrix changed")
            for sta in row["sta"]:
                log = (folder / f"{sta['corner']}_{sta['period_ns']:.3f}.log").read_text()
                if sta["period_ns"] == 6.4:
                    check_report(log, design="control_partition")
                    need(sta["exit"] == 0 and sta["report_gate"], "reference period failed")
                else:
                    need(sta["exit"] == 1 and sta["setup_slack_ns"] < 0 and "Negative setup or hold slack" in log, "main failure is not actual timing")
            area = read(folder / "area.json")["design"]
            physical.append({"experiment": label, "width": row["width"], "cells": area["num_cells"], "area_um2": area["area"],
                             "worst_setup_ns": min(s["setup_slack_ns"] for s in row["sta"]),
                             "worst_reference_setup_ns": min(s["setup_slack_ns"] for s in row["sta"] if s["period_ns"] == 6.4)})
    skill = read(STAGE / "tenure_clean_skill_gate.json")
    need(skill["ok"] and skill["errors"] == 0, "artifact gate failed")
    compatibility = read(STAGE / "compatibility.json")
    need(compatibility["exit"] == 0, "clean export failed")
    for source in (*sorted((ROOT / "rtl").rglob("*.v")), ROOT / "Makefile"):
        need(source.read_bytes() == (STAGE / "clean_export" / source.relative_to(ROOT)).read_bytes(), "adopted source differs from tested export")
    result = {"complete": True, "rtl_equivalence_widths": list(range(8, 17)), "mapped_equivalence_widths": [8, 16],
              "unit_vectors": 4856, "actual_peer_configs": 32, "identical_trace_files": count, "unit_faults": 16, "peer_faults": 56,
              "tenure_contract_proofs": 2, "tenure_fault_counterexamples": 2, "mapped_reset_proofs": 2,
              "mapped_fault_counterexamples": 6, "mapped_clock_rejections": 2, "physical": physical,
              "artifact_errors": 0, "artifact_advisories": skill["warnings"], "compatibility_exit": 0,
              "main_frequency_closed": False, "full_top_sta": False, "full_goal_complete": False}
    (STAGE / "evidence.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

"""Run: python3 [-O] verification/tl_credit_reduction/check_evidence.py.

Outputs evidence.json for actual static-slot RTL equivalence, independent vectors,
dual SRAM traces, functional/formal faults and process timing. Next close remaining
main-frequency and mapped-equivalence gaps, then the complete IP Goal.
"""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
STAGE = ROOT / "build/verification/tl_credit_reduction"


def need(condition, message):
    if not condition:
        raise ValueError(message)


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(result):
    for name, digest in result["sources"].items():
        need(sha(Path(name)) == digest, "changed source " + name)


original = read(STAGE / "original.json")
need(sha(STAGE / "original.v") == original["sha256"], "original snapshot changed")
for name in ("tl_control_decode.v", "tl_control_tenure.v"):
    content = subprocess.check_output(["git", "show", original["commit"] + ":rtl/tl/" + name], cwd=ROOT)
    need(hashlib.sha256(content).hexdigest() == sha(ROOT / "rtl/tl" / name), "shared decoder changed")
widths = []
for label in ("proved_low", "proved_middle", "proved_high"):
    folder = STAGE / label
    result = read(folder / "results.json")
    identity(result)
    need(result["complete"] and result["all_passed"] and result["output_bits"] == 123, "incomplete RTL proof")
    need(result["original_sha256"] == original["sha256"] and sha(folder / "original.v") == original["sha256"],
         "proof must use the preserved original RTL")
    need(sha(folder / "candidate.v") == sha(ROOT / "rtl/tl/tl_credit_admission.v"), "wrong candidate")
    for row in result["results"]:
        width = row["width"]
        need(row["passed"] and row["exit"] == 0 and row["proved_queries"] == 23, "unproven query")
        script = (folder / f"width{width}.ys").read_text()
        wrapper = (folder / f"miter{width}.sv").read_text()
        log = (folder / f"width{width}.log").read_text()
        need(log.count("SAT proof finished - no model found: SUCCESS!") == 23 and "ERROR:" not in log,
             "actual solver completion denominator")
        queries = re.findall(r"^sat .*", script, re.M)
        need(len(queries) == 23, "all 20 slots and 3 flags must be checked")
        for j, query in enumerate(queries):
            expected = f"sat -verify -timeout 90 -prove compare{j} 1"
            if j >= 20:
                expected += " -set requirements_equal 1"
            need(query == expected + " admission_miter", "undeclared assumption or incomplete comparison")
        need("-cut" not in script and "-input" not in script and "-ignore" not in script,
             "proof must not cut drivers or ignore cells")
        for port in ("i_rstn", "i_control", "i_done", "i_shared", "i_half", "i_available", "i_capacity"):
            need(wrapper.count(f".{port}({port})") == 2, "both actual RTL instances need the same external input")
        need(f"input wire [{20*(width+1)-1}:0] i_available,i_capacity" in wrapper,
             "proof capacity width mismatch")
        need("output wire requirements_equal" in wrapper and
             "assign requirements_equal = gold_need==gate_need;" in wrapper,
             "conditional flag lemma must be driven by the proven real requirements")
        for j in range(20):
            need(f"assign compare{j}=gold_need[{j*6}+:6]==gate_need[{j*6}+:6];" in wrapper,
                 "missing six-bit slot comparison")
        for j in range(20, 23):
            need(f"assign compare{j}=gold_flags[{j-20}]==gate_flags[{j-20}];" in wrapper,
                 "missing flag comparison")
        widths.append(width)
need(sorted(widths) == list(range(8, 17)), "exact nine-width proof matrix")

unit_vectors = {}
for stage, count in (("tl_credit_admission", 8371), ("tl_control_partition", 2428)):
    folder = ROOT / "build/verification" / stage / "static_reduction"
    result = read(folder / "results.json")
    identity(result)
    need(len(result["results"]) == 2, "unit width denominator")
    for row in result["results"]:
        need(row["compile_exit"] == row["run_exit"] == 0 and row["vectors"] == count, "actual vector failure")
        need("PASS " in (folder / f"w{row['width']}" / "run.log").read_text(), "missing simulation pass")
    unit_vectors[stage] = 2 * count

checks_folder = ROOT / "build/verification/tl_credit_admission/static_reduction_checks"
checks = read(checks_folder / "results.json")
identity(checks)
need(checks["complete"] and all(r["passed"] for r in checks["results"]), "failed external checks")
for kind, total in (("lint", 2), ("synth", 2), ("invalid_parameter", 2), ("guard_fault", 6), ("wrapper_fault", 16)):
    need(sum(r["kind"] == kind for r in checks["results"]) == total, "external gate denominator " + kind)
for row in checks["results"]:
    if row["kind"] == "guard_fault":
        folder = ROOT / "build/verification/tl_credit_admission" / ("static_reduction_checks_fault_" + row["name"])
        result = read(folder / "results.json")
        identity(result)
        need(len(result["results"]) == 2 and all(r["compile_exit"] == 0 and r["run_exit"] == 1
             for r in result["results"]), "compile/timeout cannot replace actual fault detection")
        for width in (8, 16):
            need("FATAL:" in (folder / f"w{width}" / "run.log").read_text(), "missing actual RTL fault")
    if row["kind"] == "wrapper_fault":
        need("unfunded header sent" in (checks_folder / ("bypass_" + row["config"] + ".log")).read_text(),
             "missing actual wrapper bypass failure")

formal = read(STAGE / "formal_faults.json")
need(formal["complete"] and len(formal["results"]) == 3, "formal negative denominator")
for row in formal["results"]:
    folder = STAGE / ("formal_" + row["fault"])
    need(row["caught"] and row["capture_exit"] == row["compile_exit"] == row["replay_exit"] == 0,
         "formal difference must replay in actual RTL")
    need("proof did fail!" in (folder / "width8.log").read_text(), "missing formal failure")
    need("model found: FAIL!" in (folder / "counterexample/capture.log").read_text(), "missing SAT model")
    need("PASS concrete formal fault" in (folder / "counterexample/run.log").read_text(), "missing concrete replay")

peer_root = ROOT / "build/verification/tl_control_partition"
peers = read(peer_root / "reduction_evidence.json")
need(peers["actual_configs"] == 32 and peers["scope"] == "actual_peer_traces_only", "peer scope")
identical_traces = 0
for old, new in (("peers_semantics", "reduction_peers"), ("minimum_semantics", "reduction_minimum")):
    result = read(peer_root / new / "results.json")
    identity(result)
    need(result["complete"] and len(result["results"]) == 16, "actual peer matrix")
    for row in result["results"]:
        case = f"w{row['width']}_a{row['auth']}_s{row['shared']}_l{row['delay']}"
        for name in ("trace.txt", "queue_trace.txt", "partition_trace.txt"):
            need(sha(peer_root / old / case / name) == sha(peer_root / new / case / name), "changed cycle trace")
            identical_traces += 1

timing_root = ROOT / "build/verification/tl_control_partition_timing"
timing = read(timing_root / "static_reduction/evidence.json")
baseline = read(timing_root / "mapped_baseline/evidence.json")
need(timing["audit_complete"] and timing["actual_sta_runs"] == 20, "missing timing audit")
changes = []
for old, new in zip(baseline["widths"], timing["widths"]):
    need(old["width"] == new["width"] and new["ff_bits"] == 4 and new["raw_clock"], "state changed")
    changes.append({"width": new["width"], "old_cells": old["mapped_cells"], "new_cells": new["mapped_cells"],
                    "old_area_um2": old["cell_area_um2"], "new_area_um2": new["cell_area_um2"],
                    "worst_setup_ns": min(r["setup_slack_ns"] for r in new["timing"]),
                    "worst_reference_setup_ns": min(r["setup_slack_ns"] for r in new["timing"] if r["period_ns"] == 6.4)})
gate = read(STAGE / "skill_gate.json")
need(gate["ok"] and gate["errors"] == 0, "artifact gate failed")
compatibility = read(STAGE / "compatibility.json")
need(compatibility["exit"] == 0, "clean-export regression failed")
for file in list((ROOT / "rtl").rglob("*.v")) + [ROOT / "Makefile"]:
    need(sha(file) == sha(STAGE / "clean_export" / file.relative_to(ROOT)), "RTL changed after compatibility")

result = {"complete": True, "rtl_equivalence_widths": sorted(widths), "proved_sat_queries": 207,
          "proof_scope": "binary combinational; 20 unconditional slot lemmas then 3 flags per width",
          "protocol_assumptions": [], "unit_vectors": unit_vectors, "actual_peer_configs": 32,
          "identical_cycle_trace_files": identical_traces, "unit_faults": 12, "actual_wrapper_faults": 16,
          "formal_faults_replayed": 3, "timing_changes": changes, "passed_sta_runs": timing["passed_sta_runs"],
          "artifact_errors": 0, "artifact_advisories": gate["warnings"], "compatibility_exit": 0,
          "main_frequency_closed": False, "mapped_equivalence_closed": False,
          "full_top_sta": False, "full_goal_complete": False}
(STAGE / "evidence.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))

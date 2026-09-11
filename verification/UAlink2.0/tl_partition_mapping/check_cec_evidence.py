"""Run: python3 [-O] verification/tl_partition_mapping/check_cec_evidence.py.
Writes cec_evidence.json only after actual reset, CEC and mapped fault audits.
Next close main-clock timing and full integrated IP requirements separately.
"""
from pathlib import Path
import json
import re

from check_evidence import audit_run
from run_cec import BASE, MAPPED, ROOT, dump, mutate, named_blif, need, sha


def audit_cec(label, fault):
    stage = BASE / label
    result = json.loads((stage / "results.json").read_text())
    need(result["complete"] and result["widths"] == [8, 16], "incomplete CEC matrix")
    need(result["fault"] == fault and result["all_equivalent"] == (fault is None), "incorrect CEC aggregate")
    need(result["scope"] == "binary same-state outputs and next-state functions", "wrong proof scope")
    need(sha(stage / "runner.py") == result["runner_sha256"], "changed executed runner snapshot")
    for name, digest in result["sources"].items():
        need(sha(ROOT / name) == digest, "changed measured source: " + name)
    need(sha(Path(result["library"]["path"])) == result["library"]["sha256"], "changed actual Liberty")
    need([row["width"] for row in result["results"]] == [8, 16], "missing or duplicate CEC width")
    timing = []
    for row in result["results"]:
        folder = stage / f"width{row['width']}"
        healthy = MAPPED / f"width{row['width']}/mapped.v"
        need(sha(healthy) == row["healthy_netlist_sha256"], "changed measured mapped netlist")
        need(sha(folder / "mapped.v") == row["netlist_sha256"] and
             mutate(healthy.read_text(), fault) == (folder / "mapped.v").read_text(), "undeclared netlist alteration")
        need(row["prepare"]["exit"] == 0, "preparation did not finish")
        preparation = (folder / "prepare.tcl").read_text()
        need(preparation.count("yosys techmap\n") == 2 and preparation.count("yosys dffunmap\n") == 2 and
             preparation.count("yosys opt_clean -purge\n") == 2 and "yosys synth" not in preparation,
             "direct RTL proof must use the declared lowering, not the mapped synthesis path")
        need("-ignore_unknown_cells" not in preparation and "-cut" not in preparation and
             "yosys connect" not in preparation and "yosys setundef" not in preparation,
             "proof preparation must preserve actual drivers")
        for side in ("gold", "gate"):
            graph = json.loads((folder / f"{side}.json").read_text())["modules"][side]
            encoded, metadata = named_blif((folder / f"{side}.blif").read_text(), graph, row["width"])
            need(encoded == (folder / f"{side}_named.blif").read_text(), "state renaming or cone pruning changed")
            need(metadata == json.loads((folder / f"{side}_naming.json").read_text()), "state/cone inventory changed")
            need(metadata["added_inputs"] == 0 and metadata["removed_storage_cells"] == 0,
                 "proof must retain all actual latches and original inputs")
        command = f'cec -T 90 -v "{folder}/gold_named.blif" "{folder}/gate_named.blif"\n'
        need((folder / "cec_command.txt").read_text() == command, "CEC must match named original inputs/outputs and state")
        log = (folder / "cec.log").read_text()
        need(row["cec"]["exit"] == 0 and not re.search(r"Warning:|Error:|ERROR:", log), "CEC warning/error/timeout")
        if fault is None:
            need(row["equivalent"] and not row["actual_mismatch"] and log.count("Networks are equivalent.") == 1,
                 "actual CEC equivalence was not established")
            timing.append({"width": row["width"], "seconds": row["cec"]["seconds"]})
        else:
            need(not row["equivalent"] and row["actual_mismatch"] and "Networks are NOT EQUIVALENT." in log,
                 "actual CEC did not reject mapped fault")
            need(row["witness"]["exit"] == 1 and (folder / "counterexample.json").is_file(), "missing actual SAT counterexample")
            proof = (folder / "witness.ys").read_text()
            target = "cmp_r_cursor" if fault == "transition" else "cmp_o_tags"
            options = "-seq 2 -set-at 1 cmp_r_cursor 1 -set-at 1 in_i_rstn 1 -prove-skip 1" if fault == "transition" else "-seq 1 -set cmp_r_cursor 1 -set in_i_rstn 1"
            expected = f"sat -verify -timeout 60 {options} -prove {target} 1 -dump_json {folder}/counterexample.json partition_miter"
            need(re.findall(r"^sat .*", proof, re.M) == [expected], "fault witness must check post-reset logic with reset inactive")
            need("proof did fail" in (folder / "witness.log").read_text(), "fault run was a tool error rather than SAT mismatch")
    return timing


def main():
    audit_run("reset_verified", None)
    audit_run("reset_bypass", "reset")
    audit_run("clock_mutation", "clock")
    timings = audit_cec("cec_closed", None)
    audit_cec("cec_transition_checked", "transition")
    audit_cec("cec_tags_checked", "tags")
    result = {"audit_passed": True, "mapped_equivalence_closed": True, "widths": [8, 16],
              "scope": "tl_control_partition and its three dependencies; binary behavior after one reset edge",
              "original_output_ports": 10, "original_output_bits": 529, "next_state_bits": 4,
              "reset_base_proved": True, "all_state_and_clock_correspondence_checked": True,
              "protocol_input_assumptions": [], "retiming_or_state_encoding_assumptions": [],
              "cec_timings": timings, "actual_transition_faults": 2, "actual_tag_faults": 2,
              "actual_reset_faults": 2, "actual_clock_faults": 2,
              "x_propagation_proof": False, "main_clock_timing_closed": False,
              "full_top_sta": False, "full_goal_complete": False}
    dump(BASE / "cec_evidence.json", result)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

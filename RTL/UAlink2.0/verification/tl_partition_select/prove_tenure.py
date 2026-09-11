"""Run: python3 verification/tl_partition_select/prove_tenure.py --candidate FILE.
Outputs actual default/parallel descriptor SAT proofs and two RTL fault witnesses
under build/verification/tl_partition_select/tenure_contract. Next verify the
partitioner's mandatory error gate, full integration and actual process timing.
"""
from pathlib import Path
import argparse
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "verification/tl_partition_mapping"))
from run_cec import dump, execute, need, sha

REFERENCE = "e34ea20a9c44df326f97c7da6d0e75bac5d49afe"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    args = parser.parse_args()
    stage = ROOT / "build/verification/tl_partition_select/tenure_contract"
    stage.mkdir(parents=True, exist_ok=False)
    original = subprocess.check_output(["git", "show", REFERENCE + ":rtl/tl/tl_control_tenure.v"], cwd=ROOT).decode()
    candidate = args.candidate.read_text()
    anchor = "d0[0 +: 4]=4'd2; // 单Beat读响应"
    need(candidate.count(anchor) == 1, "requires one actual single-Beat count fault target")
    (stage / "original.v").write_text(original)
    (stage / "candidate.v").write_text(candidate)
    (stage / "runner.py").write_bytes(Path(__file__).read_bytes())
    result = {"reference": REFERENCE, "candidate_sha256": sha(stage / "candidate.v"),
              "original_sha256": sha(stage / "original.v"), "results": [], "complete": False}
    dump(stage / "results.json", result)
    for parallel, fault in ((False, False), (True, False), (False, True), (True, True)):
        folder = stage / (f"parallel{int(parallel)}_fault{int(fault)}")
        folder.mkdir()
        text = candidate.replace(anchor, "d0[0 +: 4]=4'd0; // 实际故障：丢失单Beat读回复Data信用") if fault else candidate
        (folder / "candidate.v").write_text(text)
        (folder / "gold.v").write_text(original.replace("module tl_control_tenure", "module gold", 1))
        (folder / "gate.v").write_text(text.replace("module tl_control_tenure", "module gate", 1))
        parameter = "#(.ZERO_ON_ERROR(1'b0))" if parallel else ""
        condition = "(gold_status!=2'd0)||" if parallel else ""
        (folder / "miter.sv").write_text(f"""module miter(input wire [255:0] i_half,output wire o_match);
wire [1:0] gold_status,gate_status;wire [3:0] gold_fields,gate_fields;
wire [31:0] gold_counts,gate_counts;wire [7:0] gold_be,gate_be;
gold Gold(i_half,gold_status,gold_fields,gold_counts,gold_be);
gate {parameter} Gate(i_half,gate_status,gate_fields,gate_counts,gate_be);
assign o_match=(gold_status==gate_status)&&({condition}({{gold_fields,gold_counts,gold_be}}=={{gate_fields,gate_counts,gate_be}}));
endmodule
""")
        (folder / "prove.tcl").write_text(f"""yosys read_verilog {{{folder}/gold.v}} {{{folder}/gate.v}} {{{folder}/miter.sv}}
yosys prep -top miter -flatten
yosys opt -full
yosys check -assert
yosys sat -verify -timeout 60 -prove o_match 1 -show-inputs -show-outputs -dump_json {{{folder}/counterexample.json}}
""")
        row = {"parallel": parallel, "fault": fault, "source_sha256": sha(folder / "candidate.v"),
               "tool": execute(["yosys", "-Q", "-T", "-c", str(folder / "prove.tcl")], folder / "prove.log", 90)}
        log = (folder / "prove.log").read_text()
        row["passed"] = (row["tool"]["exit"] == 1 and "proof did fail" in log and (folder / "counterexample.json").is_file()) if fault else (row["tool"]["exit"] == 0 and "SAT proof finished - no model found: SUCCESS!" in log)
        result["results"].append(row)
        dump(stage / "results.json", result)
        print(parallel, fault, row["passed"], flush=True)
    result.update(complete=True, all_passed=all(r["passed"] for r in result["results"]))
    dump(stage / "results.json", result)
    return 0 if result["all_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

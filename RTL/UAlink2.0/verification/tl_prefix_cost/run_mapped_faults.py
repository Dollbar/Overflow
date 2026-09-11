"""Run: python3 verification/tl_prefix_cost/run_mapped_faults.py.
Optional --proof-label NAME and --label NAME preserve separate stages.
Writes actual mapped reset proofs and clock/transition/tag fault evidence under
build/verification/tl_prefix_cost/mapped_faults. Next audit all RTL and STA gates.
"""
from pathlib import Path
import argparse
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "verification/tl_partition_mapping"))
from run_cec import dump, execute, inspect_graph, mutate, named_blif, need, sha

BASE = ROOT / "build/verification/tl_prefix_cost"


def sat_query(folder, name, target, options):
    script = f"""read_rtlil {folder}/gold.il
read_rtlil {folder}/gate.il
miter -equiv -make_outputs -make_outcmp -flatten gold gate partition_miter
hierarchy -top partition_miter
opt -full
delete -output partition_miter/w:*
expose partition_miter/w:gold_r_cursor partition_miter/w:gate_r_cursor partition_miter/w:cmp_r_cursor partition_miter/w:{target}
opt_clean -purge
check -assert
sat -verify -timeout 60 {options} -dump_json {folder}/{name}_counterexample.json partition_miter
"""
    (folder / (name + ".ys")).write_text(script)
    result = execute(["yosys", "-Q", "-T", "-s", str(folder / (name + ".ys"))], folder / (name + ".log"), 120)
    log = (folder / (name + ".log")).read_text()
    result.update(passed=result["exit"] == 0 and "SAT proof finished - no model found: SUCCESS!" in log,
                  mismatch=result["exit"] == 1 and "proof did fail" in log)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proof-label", default="mapped_equivalence")
    parser.add_argument("--label", default="mapped_faults")
    args = parser.parse_args()
    need(all(re.fullmatch(r"[a-zA-Z0-9_-]+", s) for s in (args.proof_label, args.label)), "invalid proof or output label")
    healthy = BASE / args.proof_label
    metadata = json.loads((healthy / "results.json").read_text())
    need(metadata["complete"] and metadata["all_passed"] and metadata["widths"] == [8, 16], "requires both healthy mapped proofs")
    stage = BASE / args.label
    stage.mkdir(exist_ok=False)
    (stage / "runner.py").write_bytes(Path(__file__).read_bytes())
    result = {"complete": False, "all_passed": False, "candidate_sha256": metadata["candidate_sha256"],
              "runner_sha256": sha(Path(__file__)), "results": []}
    dump(stage / "results.json", result)
    for width in (8, 16):
        source = healthy / f"width{width}"
        expected = next(r for r in metadata["results"] if r["width"] == width)["netlist_sha256"]
        need(sha(source / "mapped.v") == expected, "healthy netlist changed")
        for fault in ("healthy_reset", "clock", "transition", "tags"):
            folder = stage / f"{fault}{width}"
            folder.mkdir()
            original = (source / "mapped.v").read_text()
            altered = original
            if fault in ("transition", "tags"):
                altered = mutate(original, fault)
            elif fault == "clock":
                pattern = r"DFQD2BWP40P140\s+\S+\s*\(\s*\.CP\(i_clk\),\s*\.D\([^()]+\),\s*\.Q\(r_cursor\[0\]\)\s*\);"
                cells = re.findall(pattern, original)
                need(len(cells) == 1, "clock target is not one actual mapped FF")
                altered = original.replace(cells[0], cells[0].replace(".CP(i_clk)", ".CP(1'b0)"), 1)
            (folder / "mapped.v").write_text(altered)
            row = {"width": width, "fault": fault, "healthy_netlist_sha256": expected,
                   "netlist_sha256": sha(folder / "mapped.v"), "passed": False}
            if fault == "healthy_reset":
                for name in ("gold.il", "gate.il", "gold.json", "gate.json"):
                    (folder / name).write_bytes((source / name).read_bytes())
                for side in ("gold", "gate"):
                    inspect_graph(json.loads((folder / f"{side}.json").read_text())["modules"][side], width)
                row["reset"] = sat_query(folder, "reset", "gold_r_cursor", "-seq 2 -set-at 1 in_i_rstn 0 -prove-skip 1 -prove gold_r_cursor 0 -prove gate_r_cursor 0")
                row["passed"] = row["reset"]["passed"]
            else:
                (folder / "prepare.tcl").write_text((source / "prepare.tcl").read_text().replace(str(source), str(folder)))
                row["prepare"] = execute(["yosys", "-Q", "-T", "-c", str(folder / "prepare.tcl")], folder / "prepare.log", 240)
                need(row["prepare"]["exit"] == 0, "fault must elaborate successfully")
                graph = json.loads((folder / "gate.json").read_text())["modules"]["gate"]
                if fault == "clock":
                    try:
                        inspect_graph(graph, width)
                    except ValueError as error:
                        row["inventory_error"] = str(error)
                        row["passed"] = True
                    else:
                        raise ValueError("wrong actual clock accepted")
                else:
                    for side in ("gold", "gate"):
                        graph = json.loads((folder / f"{side}.json").read_text())["modules"][side]
                        text, naming = named_blif((folder / f"{side}.blif").read_text(), graph, width)
                        (folder / f"{side}_named.blif").write_text(text)
                        dump(folder / f"{side}_naming.json", naming)
                    command = f'cec -T 90 -v "{folder}/gold_named.blif" "{folder}/gate_named.blif"'
                    (folder / "command.txt").write_text(command + "\n")
                    row["cec"] = execute(["yosys-abc", "-c", command], folder / "cec.log", 150)
                    need(row["cec"]["exit"] == 0 and "Networks are NOT EQUIVALENT." in (folder / "cec.log").read_text(), "mapped fault was not rejected by CEC")
                    if fault == "transition":
                        row["transition"] = sat_query(folder, "transition", "cmp_r_cursor", "-seq 2 -set-at 1 cmp_r_cursor 1 -set-at 1 in_i_rstn 1 -prove-skip 1 -prove cmp_r_cursor 1")
                        row["reset"] = sat_query(folder, "reset", "gold_r_cursor", "-seq 2 -set-at 1 in_i_rstn 0 -prove-skip 1 -prove gold_r_cursor 0 -prove gate_r_cursor 0")
                        row["passed"] = row["transition"]["mismatch"] and row["reset"]["mismatch"]
                    else:
                        row["tags"] = sat_query(folder, "tags", "cmp_o_tags", "-seq 1 -set cmp_r_cursor 1 -set in_i_rstn 1 -prove cmp_o_tags 1")
                        row["passed"] = row["tags"]["mismatch"]
            result["results"].append(row)
            dump(stage / "results.json", result)
            print(width, fault, row["passed"], flush=True)
    result["complete"] = True
    result["all_passed"] = len(result["results"]) == 8 and all(row["passed"] for row in result["results"])
    dump(stage / "results.json", result)
    return 0 if result["all_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

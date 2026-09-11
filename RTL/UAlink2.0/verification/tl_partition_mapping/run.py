"""Run: python3 verification/tl_partition_mapping/run.py --widths 8 16.
Outputs real reset/induction/output proof logs and source-bound mapped artifacts in
build/verification/tl_partition_mapping. Next audit all obligations; timing is separate.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import signal
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUTPUT_WIDTHS = {"o_valid": 1, "o_taken": 1, "o_source_taken": 1, "o_error": 1,
                 "o_shortfall": 1, "o_control": 256, "o_tags": 256, "o_fields": 4,
                 "o_end": 4, "o_cursor": 4}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_inventory(graph):
    ff = [c for c in graph["cells"].values() if "DFF" in c["type"] or "LATCH" in c["type"]]
    actual_state = {bit for c in ff for bit in c["connections"].get("Q", [])}
    observed_state = set(graph["ports"]["gold_r_cursor"]["bits"] + graph["ports"]["gate_r_cursor"]["bits"])
    if len(ff) != 8 or len(actual_state) != 8 or actual_state != observed_state or any(
        c["type"] not in ("$_SDFFE_PN0P_", "$_DFF_P_") or
        c["connections"]["C"] != graph["ports"]["in_i_clk"]["bits"] for c in ff):
        raise ValueError("actual state/clock inventory differs from the complete four-bit cursor relation")
    return {"gold_state_bits": 4, "gate_state_bits": 4, "all_state_observed": True,
            "common_raw_clock": True, "extra_state_inputs": False}


def check_outputs(graph):
    for side in ("gold", "gate"):
        found = {name[len(side) + 1:]: len(port["bits"])
                 for name, port in graph["ports"].items() if name.startswith(side + "_o_")}
        if found != OUTPUT_WIDTHS:
            raise ValueError("original output coverage changed: " + side)
    for name in ("r_cursor", *OUTPUT_WIDTHS):
        if len(graph["ports"].get("cmp_" + name, {}).get("bits", [])) != 1:
            raise ValueError("missing actual comparison " + name)
    return {"original_ports": len(OUTPUT_WIDTHS), "original_bits": sum(OUTPUT_WIDTHS.values()),
            "observed_state_bits": 4}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--widths", type=int, nargs="+", default=[8, 16])
    parser.add_argument("--label", default="relational")
    parser.add_argument("--reset-only", action="store_true", help="prove only one-edge zero-state reset")
    parser.add_argument("--fault", choices=("reset", "clock"), help="mutate one real mapped cursor flip-flop")
    args = parser.parse_args()
    if len(set(args.widths)) != len(args.widths) or any(w not in (8, 16) for w in args.widths) or not re.fullmatch(r"[a-zA-Z0-9_-]+", args.label):
        parser.error("invalid width/label")
    if args.fault and not args.reset_only:
        parser.error("mapped faults are currently audited only in reset-only mode")
    base = ROOT / "build/verification/tl_control_partition_timing/static_reduction"
    mapping = json.loads((base / "results.json").read_text())
    for name, digest in mapping["sources"].items():
        if sha(ROOT / name) != digest:
            raise ValueError("mapped-source mismatch: " + name)
    library = Path(mapping["libraries"]["ssg0p81v125c"]["path"])
    if sha(library) != mapping["libraries"]["ssg0p81v125c"]["sha256"]:
        raise ValueError("mapped library changed")
    stage = ROOT / "build/verification/tl_partition_mapping" / args.label
    stage.mkdir(parents=True, exist_ok=False)
    result = {"complete": False, "all_passed": False, "sources": mapping["sources"],
              "library": {"path": str(library), "sha256": sha(library)}, "results": [],
              "requested_widths": args.widths, "scope": "reset" if args.reset_only else "sequential_equivalence",
              "fault": args.fault, "mapped_equivalence_closed": False,
              "runner_sha256": sha(Path(__file__)), "binary_boolean_scope": True}
    (stage / "runner.py").write_bytes(Path(__file__).read_bytes())

    def save():
        (stage / "results.json").write_text(json.dumps(result, indent=2) + "\n")

    def run(command, log):
        with log.open("w") as stream:
            try:
                process = subprocess.Popen(command, cwd=ROOT, stdout=stream,
                                           stderr=subprocess.STDOUT, start_new_session=True)
                return process.wait(timeout=600)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                return 124

    save()
    for width in args.widths:
        folder = stage / f"width{width}"
        folder.mkdir()
        netlist = base / f"width{width}/mapped.v"
        recorded = next(r for r in mapping["widths"] if r["width"] == width)
        if sha(netlist) != recorded["netlist_sha256"]:
            raise ValueError("mapped netlist changed")
        healthy_sha = sha(netlist)
        netlist_text = netlist.read_text()
        if args.fault:
            pattern = r"(DFQD2BWP40P140\s+\S+\s*\(\s*\.CP\()i_clk(\),\s*\.D\()[^()]+(\),\s*\.Q\(r_cursor\[0\]\)\s*\);)"
            match = re.search(pattern, netlist_text)
            if match is None or len(re.findall(pattern, netlist_text)) != 1:
                raise ValueError("expected exactly one actual cursor[0] mapped FF")
            original_cell = match.group(0)
            replacement = original_cell.replace(".CP(i_clk)", ".CP(1'b0)") if args.fault == "clock" else re.sub(r"\.D\([^()]+\)", ".D(i_source_valid)", original_cell)
            netlist_text = netlist_text[:match.start()] + replacement + netlist_text[match.end():]
        netlist = folder / "mapped.v"
        netlist.write_text(netlist_text)
        env = {"UALINK_LIBERTY": str(library), "UALINK_NETLIST": str(netlist), "UALINK_WIDTH": str(width)}
        script = (ROOT / "scripts/equiv_tl_control_partition.tcl").read_text()
        script = script[:script.index("yosys miter -equiv")]
        script = script.replace("set root [file dirname [file dirname [file normalize [info script]]]]",
                                "set root {" + str(ROOT) + "}")
        prefix = "".join("set env(" + key + ") {" + value + "}\n" for key, value in env.items())
        script = prefix + script + f"""yosys miter -equiv -make_outputs -make_outcmp -flatten gold gate partition_miter
yosys hierarchy -top partition_miter
yosys opt -full
yosys techmap
yosys opt -full
yosys check -assert
yosys write_json {folder}/prepared.json
yosys write_rtlil {folder}/prepared.il
"""
        preparation = folder / "prepare.tcl"
        preparation.write_text(script)
        code = run(["yosys", "-Q", "-T", "-c", str(preparation)], folder / "prepare.log")
        row = {"width": width, "netlist_sha256": sha(netlist), "healthy_netlist_sha256": healthy_sha,
               "prepare_exit": code, "queries": []}
        result["results"].append(row)
        save()
        if code:
            break
        graph = json.loads((folder / "prepared.json").read_text())["modules"]["partition_miter"]
        row["output_coverage"] = check_outputs(graph)
        try:
            row["inventory"] = check_inventory(graph)
        except ValueError as error:
            row["inventory_error"] = str(error)
            save()
            continue
        queries = [("reset", "cmp_r_cursor", "-seq 2 -set-at 1 in_i_rstn 0 -prove-skip 1"),
                   ("induction", "cmp_r_cursor", "-seq 2 -set-at 1 cmp_r_cursor 1 -prove-skip 1")]
        queries += [(name, "cmp_" + name, "-seq 1 -set cmp_r_cursor 1") for name in OUTPUT_WIDTHS]
        if args.reset_only:
            queries = [("reset_zero", "gold_r_cursor", "-seq 2 -set-at 1 in_i_rstn 0 -prove-skip 1 -prove gate_r_cursor 0")]
        for name, target, options in queries:
            proof = folder / (name + ".ys")
            observations = "gold_r_cursor partition_miter/w:gate_r_cursor" if args.reset_only else "cmp_r_cursor"
            expected = 0 if args.reset_only else 1
            proof.write_text(f"""read_rtlil {folder}/prepared.il
delete -output partition_miter/w:*
expose partition_miter/w:{target} partition_miter/w:{observations}
opt_clean -purge
check -assert
sat -verify -timeout 90 {options} -prove {target} {expected} -dump_json {folder}/{name}_counterexample.json partition_miter
""")
            code = run(["yosys", "-Q", "-T", "-s", str(proof)], folder / (name + ".log"))
            passed = code == 0 and "SAT proof finished - no model found: SUCCESS!" in (folder / (name + ".log")).read_text()
            row["queries"].append({"name": name, "target": target, "options": options, "exit": code, "passed": passed})
            save()
            print(width, name, code, flush=True)
            if not passed:
                break
        if not args.reset_only and (len(row["queries"]) != 12 or not all(q["passed"] for q in row["queries"])):
            break
    result["complete"] = True
    result["all_passed"] = len(result["results"]) == len(args.widths) and all(
        len(r["queries"]) == (1 if args.reset_only else 12) and all(q["passed"] for q in r["queries"]) for r in result["results"])
    result["mapped_equivalence_closed"] = result["all_passed"] and not args.reset_only and not args.fault
    save()
    return 0 if result["all_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

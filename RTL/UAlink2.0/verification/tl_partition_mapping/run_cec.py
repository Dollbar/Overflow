"""Run: python3 verification/tl_partition_mapping/run_cec.py --label cec_verified.
Outputs actual RTL/mapped BLIF, state correspondence, CEC and SAT witness logs
under build/verification/tl_partition_mapping. Next combine with audited reset.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import signal
import subprocess
import time

from run import OUTPUT_WIDTHS

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "build/verification/tl_partition_mapping"
MAPPED = ROOT / "build/verification/tl_control_partition_timing/static_reduction"


def need(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def execute(command, log, timeout=180):
    start = time.monotonic()
    with log.open("w") as output:
        process = subprocess.Popen(command, cwd=ROOT, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            code = 124
    return {"exit": code, "seconds": time.monotonic() - start}


def inspect_graph(graph, width):
    inputs = {name: 1 for name in ("i_clk", "i_rstn", "i_source_valid", "i_ready",
                                  "i_done", "i_response", "i_auth", "i_shared")}
    inputs.update(i_source_control=256, i_source_tags=512, i_capacity=20 * (width + 1))
    outputs = dict(OUTPUT_WIDTHS, r_cursor=4)
    for direction, expected in (("input", inputs), ("output", outputs)):
        found = {n: len(p["bits"]) for n, p in graph["ports"].items() if p["direction"] == direction}
        need(found == expected, "unexpected original port/state observation inventory")
    state = graph["ports"]["r_cursor"]["bits"]
    ff = [c for c in graph["cells"].values() if c["type"] == "$_DFF_P_"]
    need(len(ff) == 4 and len(set(state)) == 4 and
         {b for c in ff for b in c["connections"]["Q"]} == set(state), "incomplete actual state")
    need(all(c["connections"]["C"] == graph["ports"]["i_clk"]["bits"] for c in ff),
         "clock correspondence is not the original positive i_clk edge")
    allowed = {"$_DFF_P_", "$_AND_", "$_OR_", "$_XOR_", "$_NOT_", "$_MUX_"}
    drivers = [b for p in graph["ports"].values() if p["direction"] == "input" for b in p["bits"]]
    consumed = [b for p in graph["ports"].values() if p["direction"] == "output" for b in p["bits"]]
    for cell in graph["cells"].values():
        need(cell["type"] in allowed, "unknown gate or unobserved storage")
        for name, bits in cell["connections"].items():
            need(all(isinstance(b, int) or b in ("0", "1") for b in bits), "X/Z in a real logic connection")
            (drivers if cell["port_directions"][name] == "output" else consumed).extend(bits)
    driven = set(drivers)
    need(len(drivers) == len(driven) and all(isinstance(b, int) for b in drivers), "multiple/constant drivers")
    need(all(b in driven or b in ("0", "1") for b in consumed), "undriven real output/state cone")
    return {"original_output_bits": 529, "next_state_bits": 4, "state_bits": 4,
            "raw_positive_clock": True, "all_logic_inputs_driven": True, "x_z_logic_connections": 0}


def prune_dead_names(raw):
    """Drop only BLIF alias/gate definitions outside every output and next-state cone."""
    blocks = []
    for line in raw.splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        if line.startswith("."):
            need(line.split()[0] in (".model", ".inputs", ".outputs", ".names", ".latch", ".end"),
                 "unsupported BLIF directive")
            blocks.append([line])
        else:
            need(blocks and blocks[-1][0].startswith(".names "), "unexpected BLIF truth table")
            blocks[-1].append(line)
    definitions, terminals, roots = {}, set(), set()
    for block in blocks:
        words = block[0].split()
        if words[0] == ".names":
            need(words[-1] not in definitions, "duplicate BLIF driver")
            definitions[words[-1]] = words[1:-1]
        elif words[0] == ".inputs":
            terminals.update(words[1:])
        elif words[0] == ".outputs":
            roots.update(words[1:])
        elif words[0] == ".latch":
            need(len(words) == 6, "unexpected BLIF latch")
            terminals.add(words[2])
            roots.update((words[1], words[4]))
    need(not (set(definitions) & terminals), "BLIF state/input is multiply driven")
    reachable, pending = set(), list(roots)
    while pending:
        net = pending.pop()
        if net in reachable:
            continue
        reachable.add(net)
        if net in terminals:
            continue
        need(net in definitions, "undriven live BLIF cone: " + net)
        pending.extend(definitions[net])
    retained = [block for block in blocks if not block[0].startswith(".names ") or block[0].split()[-1] in reachable]
    return "\n".join(line for block in retained for line in block) + "\n", {
        "removed_dead_names": len(blocks) - len(retained), "all_output_and_latch_d_clock_roots_preserved": True}


def named_blif(raw, graph, width):
    inventory = inspect_graph(graph, width)
    lines = raw.splitlines()
    need(not any(line.startswith((".subckt", ".gate", ".blackbox")) for line in lines), "unexpanded BLIF cell")
    ports = graph["ports"]

    def names(direction):
        return {n if len(p["bits"]) == 1 else f"{n}[{i}]" for n, p in ports.items()
                if p["direction"] == direction for i in range(len(p["bits"]))}

    for directive, direction in ((".inputs", "input"), (".outputs", "output")):
        declarations = [line.split()[1:] for line in lines if line.startswith(directive + " ")]
        need(len(declarations) == 1 and len(declarations[0]) == len(names(direction)) and
             set(declarations[0]) == names(direction), "BLIF port coverage changed")

    def bit(net):
        if net in graph["netnames"] and len(graph["netnames"][net]["bits"]) == 1:
            return graph["netnames"][net]["bits"][0]
        match = re.fullmatch(r"(.*)\[(\d+)\]", net)
        need(match is not None and match[1] in graph["netnames"], "unresolved BLIF state net")
        wire = graph["netnames"][match[1]]
        need(not wire.get("upto", 0), "unsupported ascending state alias")
        return wire["bits"][int(match[2]) - wire.get("offset", 0)]

    latches = [line.split() for line in lines if line.startswith(".latch ")]
    need(len(latches) == 4, "BLIF storage denominator changed")
    state = ports["r_cursor"]["bits"]
    ff = {c["connections"]["Q"][0]: c for c in graph["cells"].values() if c["type"] == "$_DFF_P_"}
    rename = {}
    for latch in latches:
        need(len(latch) == 6 and latch[3:] == ["re", "i_clk", "2"], "BLIF clock/init changed")
        q, d = bit(latch[2]), bit(latch[1])
        need(q in ff and ff[q]["connections"]["D"] == [d], "BLIF latch differs from actual D/Q graph")
        rename[latch[2]] = f"formal_cursor[{state.index(q)}]"
    need(len(set(rename.values())) == 4 and not (set(rename.values()) & set(raw.split())), "ambiguous state names")
    trimmed, pruning = prune_dead_names(raw)
    renamed = []
    for line in trimmed.splitlines():
        if line.startswith(".outputs "):
            line = " ".join(t for t in line.split() if not re.fullmatch(r"r_cursor\[[0-3]\]", t))
        renamed.append(re.sub(r"\S+", lambda m: rename.get(m[0], m[0]), line))
    return "\n".join(renamed) + "\n", {"inventory": inventory, "state_net_renaming": rename,
                                            "dead_alias_pruning": pruning,
                                            "removed_observation_ports": [f"r_cursor[{i}]" for i in range(4)],
                                            "removed_storage_cells": 0, "added_inputs": 0}


def mutate(text, fault):
    if fault == "transition":
        pattern = r"DFQD2BWP40P140\s+\S+\s*\(\s*\.CP\(i_clk\),\s*\.D\([^()]+\),\s*\.Q\(r_cursor\[0\]\)\s*\);"
        cells = re.findall(pattern, text)
        need(len(cells) == 1, "expected one actual cursor[0] mapped flip-flop")
        return text.replace(cells[0], re.sub(r"\.D\([^()]+\)", ".D(i_source_valid)", cells[0]), 1)
    if fault == "tags":
        need(text.count(".ZN(o_tags[0])") == 1 and text.count("endmodule") == 1 and
             "fault_original_tag" not in text, "expected one actual tag[0] output gate")
        text = text.replace(".ZN(o_tags[0])", ".ZN(fault_original_tag)")
        return text.replace("endmodule", "wire fault_original_tag;\nassign o_tags[0] = 1'b0;\nendmodule")
    need(fault is None, "unknown fault")
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--widths", type=int, nargs="+", default=[8, 16])
    parser.add_argument("--label", default="cec_verified")
    parser.add_argument("--fault", choices=("transition", "tags"))
    args = parser.parse_args()
    need(len(set(args.widths)) == len(args.widths) and all(w in (8, 16) for w in args.widths), "invalid widths")
    need(re.fullmatch(r"[a-zA-Z0-9_-]+", args.label) is not None, "invalid label")
    mapping = json.loads((MAPPED / "results.json").read_text())
    for name, digest in mapping["sources"].items():
        need(sha(ROOT / name) == digest, "changed measured source " + name)
    library = Path(mapping["libraries"]["ssg0p81v125c"]["path"])
    need(sha(library) == mapping["libraries"]["ssg0p81v125c"]["sha256"], "changed actual Liberty")
    stage = BASE / args.label
    stage.mkdir(exist_ok=False)
    (stage / "runner.py").write_bytes(Path(__file__).read_bytes())
    result = {"complete": False, "all_equivalent": False, "fault": args.fault, "widths": args.widths,
              "sources": mapping["sources"], "library": {"path": str(library), "sha256": sha(library)},
              "runner_sha256": sha(Path(__file__)), "results": [], "scope": "binary same-state outputs and next-state functions"}
    dump(stage / "results.json", result)
    for width in args.widths:
        folder = stage / f"width{width}"
        folder.mkdir()
        healthy = MAPPED / f"width{width}/mapped.v"
        recorded = next(r for r in mapping["widths"] if r["width"] == width)
        need(sha(healthy) == recorded["netlist_sha256"], "changed measured mapped netlist")
        (folder / "mapped.v").write_text(mutate(healthy.read_text(), args.fault))
        script = "".join(f"set env({k}) {{{v}}}\n" for k, v in {
            "UALINK_WIDTH": width, "UALINK_LIBERTY": library, "UALINK_NETLIST": folder / "mapped.v"}.items())
        prefix = (ROOT / "scripts/equiv_tl_control_partition.tcl").read_text()
        prefix = prefix[:prefix.index("yosys miter -equiv")]
        prefix = prefix.replace("set root [file dirname [file dirname [file normalize [info script]]]]", "set root {" + str(ROOT) + "}")
        script += prefix + "yosys design -save paired\n"
        for side in ("gold", "gate"):
            script += f"""yosys design -load paired
yosys hierarchy -top {side}
yosys techmap
yosys opt -full
yosys dffunmap
yosys opt_clean -purge
yosys check -assert
yosys write_json {{{folder}/{side}.json}}
yosys write_rtlil {{{folder}/{side}.il}}
yosys write_blif {{{folder}/{side}.blif}}
"""
        (folder / "prepare.tcl").write_text(script)
        row = {"width": width, "healthy_netlist_sha256": sha(healthy), "netlist_sha256": sha(folder / "mapped.v"),
               "prepare": execute(["yosys", "-Q", "-T", "-c", str(folder / "prepare.tcl")], folder / "prepare.log"), "equivalent": False}
        result["results"].append(row)
        dump(stage / "results.json", result)
        if row["prepare"]["exit"]:
            break
        for side in ("gold", "gate"):
            graph = json.loads((folder / f"{side}.json").read_text())["modules"][side]
            text, naming = named_blif((folder / f"{side}.blif").read_text(), graph, width)
            (folder / f"{side}_named.blif").write_text(text)
            dump(folder / f"{side}_naming.json", naming)
        command = f'cec -T 90 -v "{folder}/gold_named.blif" "{folder}/gate_named.blif"'
        (folder / "cec_command.txt").write_text(command + "\n")
        row["cec"] = execute(["yosys-abc", "-c", command], folder / "cec.log", 150)
        log = (folder / "cec.log").read_text()
        row["equivalent"] = row["cec"]["exit"] == 0 and log.count("Networks are equivalent.") == 1 and not re.search(r"Warning:|Error:|ERROR:", log)
        row["actual_mismatch"] = row["cec"]["exit"] == 0 and "Networks are NOT EQUIVALENT." in log
        if args.fault and row["actual_mismatch"]:
            target = "cmp_r_cursor" if args.fault == "transition" else "cmp_o_tags"
            options = "-seq 2 -set-at 1 cmp_r_cursor 1 -set-at 1 in_i_rstn 1 -prove-skip 1" if args.fault == "transition" else "-seq 1 -set cmp_r_cursor 1 -set in_i_rstn 1"
            proof = f"""read_rtlil {folder}/gold.il
read_rtlil {folder}/gate.il
miter -equiv -make_outputs -make_outcmp -flatten gold gate partition_miter
hierarchy -top partition_miter
opt -full
delete -output partition_miter/w:*
expose partition_miter/w:{target} partition_miter/w:cmp_r_cursor
opt_clean -purge
check -assert
sat -verify -timeout 60 {options} -prove {target} 1 -dump_json {folder}/counterexample.json partition_miter
"""
            (folder / "witness.ys").write_text(proof)
            row["witness"] = execute(["yosys", "-Q", "-T", "-s", str(folder / "witness.ys")], folder / "witness.log", 120)
        dump(stage / "results.json", result)
        print(width, row["equivalent"], row["actual_mismatch"], flush=True)
    result["complete"] = True
    result["all_equivalent"] = len(result["results"]) == len(args.widths) and all(r["equivalent"] for r in result["results"])
    dump(stage / "results.json", result)
    return 0 if result["all_equivalent"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

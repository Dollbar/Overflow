"""Run: python3 verification/tl_prefix_cost/run_equivalence.py --candidate FILE --label NAME.
Optional --widths 8 ... 16, or --mapped-root DIR --liberty FILE for actual mapped
equivalence (WIDTH8/16). --reference accepts a full Git commit; --dependency-root
selects gate dependencies while gold uses the reference snapshot. Outputs under
build/verification/tl_prefix_cost. Next audit reset, faults, integration and timing.
"""
from pathlib import Path
import argparse
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "verification/tl_partition_mapping"))
from run_cec import dump, execute, named_blif, need, sha

REFERENCE = "1bc57c143d3d87ac8f638e0990ee19024b474005"
DEPENDENCIES = ("tl_credit_admission.v", "tl_control_decode.v", "tl_control_tenure.v")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--widths", type=int, nargs="+", default=list(range(8, 17)))
    parser.add_argument("--mapped-root", type=Path)
    parser.add_argument("--liberty", type=Path)
    parser.add_argument("--reference", default=REFERENCE, help="immutable full reference commit")
    parser.add_argument("--dependency-root", type=Path, help="candidate dependency directory; gold always uses reference Git sources")
    args = parser.parse_args()
    need(args.candidate.is_file() and re.fullmatch(r"[a-zA-Z0-9_-]+", args.label), "invalid candidate or label")
    need(len(set(args.widths)) == len(args.widths) and all(8 <= w <= 16 for w in args.widths), "invalid width matrix")
    need(re.fullmatch(r"[0-9a-f]{40}", args.reference), "reference must be a full immutable commit")
    need(bool(args.mapped_root) == bool(args.liberty), "mapped proof needs both actual netlists and Liberty")
    if args.mapped_root:
        need(all(w in (8, 16) for w in args.widths) and args.liberty.is_file(), "invalid mapped proof inputs")
    stage = ROOT / "build/verification/tl_prefix_cost" / args.label
    stage.mkdir(parents=True, exist_ok=False)
    (stage / "candidate.v").write_bytes(args.candidate.read_bytes())
    original = subprocess.check_output(["git", "show", args.reference + ":rtl/tl/tl_control_partition.v"], cwd=ROOT)
    (stage / "original.v").write_bytes(original)
    dependencies, original_dependencies = [], []
    (stage / "reference_dependencies").mkdir()
    for name in DEPENDENCIES:
        source = (args.dependency_root or ROOT / "rtl/tl") / name
        reference_source = subprocess.check_output(["git", "show", args.reference + ":rtl/tl/" + name], cwd=ROOT)
        if not args.dependency_root:
            need(source.read_bytes() == reference_source, "shared decoder/admission changed since reference")
        (stage / "reference_dependencies" / name).write_bytes(reference_source)
        original_dependencies.append(stage / "reference_dependencies" / name)
        (stage / name).write_bytes(source.read_bytes())
        dependencies.append(stage / name)
    (stage / "runner.py").write_bytes(Path(__file__).read_bytes())
    support = ROOT / "verification/tl_partition_mapping/run_cec.py"
    (stage / "cec_support.py").write_bytes(support.read_bytes())
    result = {"complete": False, "all_passed": False, "widths": args.widths,
              "mode": "mapped" if args.mapped_root else "rtl", "reference": args.reference,
              "candidate_sha256": sha(stage / "candidate.v"), "original_sha256": sha(stage / "original.v"),
              "dependencies": {p.name: sha(p) for p in dependencies}, "results": [],
              "reference_dependencies": {p.name: sha(p) for p in original_dependencies},
              "runner_sha256": sha(Path(__file__)), "support_sha256": sha(support),
              "original_output_bits": 529, "next_state_bits": 4, "protocol_assumptions": []}
    if args.liberty:
        result["library"] = {"path": str(args.liberty.resolve()), "sha256": sha(args.liberty)}
    dump(stage / "results.json", result)
    for width in args.widths:
        folder = stage / f"width{width}"
        folder.mkdir()
        script = ""
        for side in ("gold", "gate"):
            script += "yosys design -reset\n"
            if side == "gate" and args.mapped_root:
                mapped = args.mapped_root / f"width{width}/mapped.v"
                need(mapped.is_file(), "missing actual mapped netlist")
                (folder / "mapped.v").write_bytes(mapped.read_bytes())
                script += f"yosys read_liberty -ignore_miss_func {{{args.liberty.resolve()}}}\nyosys read_verilog {{{folder}/mapped.v}}\n"
            else:
                primary = stage / ("original.v" if side == "gold" and not args.mapped_root else "candidate.v")
                side_dependencies = original_dependencies if side == "gold" and not args.mapped_root else dependencies
                for source in (primary, *side_dependencies):
                    script += f"yosys read_verilog {{{source}}}\n"
                script += f"yosys chparam -set WIDTH {width} tl_control_partition\n"
            script += f"""yosys prep -top tl_control_partition -flatten
yosys rename -top {side}
yosys expose {side}/w:r_cursor
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
        row = {"width": width, "passed": False, "prepare": execute(["yosys", "-Q", "-T", "-c", str(folder / "prepare.tcl")], folder / "prepare.log", 240)}
        if args.mapped_root:
            row["netlist_sha256"] = sha(folder / "mapped.v")
        result["results"].append(row)
        dump(stage / "results.json", result)
        if row["prepare"]["exit"]:
            break
        for side in ("gold", "gate"):
            graph = json.loads((folder / f"{side}.json").read_text())["modules"][side]
            text, metadata = named_blif((folder / f"{side}.blif").read_text(), graph, width)
            (folder / f"{side}_named.blif").write_text(text)
            dump(folder / f"{side}_naming.json", metadata)
        command = f'cec -T 120 -v "{folder}/gold_named.blif" "{folder}/gate_named.blif"'
        (folder / "cec_command.txt").write_text(command + "\n")
        row["cec"] = execute(["yosys-abc", "-c", command], folder / "cec.log", 180)
        log = (folder / "cec.log").read_text()
        row["passed"] = row["cec"]["exit"] == 0 and log.count("Networks are equivalent.") == 1 and not re.search(r"Warning:|Error:|ERROR:", log)
        dump(stage / "results.json", result)
        print(width, row["passed"], flush=True)
        if not row["passed"]:
            break
    result["complete"] = True
    result["all_passed"] = len(result["results"]) == len(args.widths) and all(r["passed"] for r in result["results"])
    dump(stage / "results.json", result)
    return 0 if result["all_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

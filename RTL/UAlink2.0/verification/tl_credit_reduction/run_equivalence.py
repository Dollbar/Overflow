"""Run: python3 verification/tl_credit_reduction/run_equivalence.py [--label NAME]
[--reference-commit COMMIT] [--replace FILE] [--widths 8 ... 16].

Outputs: original/candidate snapshots, complete-input SAT miters and real proof logs
under build/verification/tl_credit_reduction/<label>. Next audit all nine widths and
actual functional mutants, then repeat integrated peers and process timing.
The reference is an immutable Git source. Each slot is proved without assumptions;
flag queries use only the equality discharged by the preceding 20 slot lemmas.
This is binary Boolean equivalence, with no protocol legality assumptions or cut inputs.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
LEGACY_REFERENCE = "4376b8bbbea936be528039eaa71983afc7fc865f"


def cache_legacy_reference(folder, reference, original):
    """Preserve the historical auditor's cache without mixing explicit references."""
    if reference != LEGACY_REFERENCE:
        return
    baseline, metadata = folder / "original.v", folder / "original.json"
    expected = {"commit": reference, "sha256": hashlib.sha256(original).hexdigest()}
    if baseline.exists() or metadata.exists():
        if not baseline.is_file() or not metadata.is_file() or baseline.read_bytes() != original or json.loads(metadata.read_text()) != expected:
            raise ValueError("stage reference differs from the requested immutable original")
    else:
        baseline.write_bytes(original)
        metadata.write_text(json.dumps(expected, indent=2) + "\n")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--label", default="cone_equivalence")
    p.add_argument("--reference-commit", default=LEGACY_REFERENCE)
    p.add_argument("--replace", type=Path)
    p.add_argument("--widths", type=int, nargs="+", default=list(range(8, 17)))
    a = p.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", a.label) or any(w not in range(8, 17) for w in a.widths):
        p.error("invalid label/width")
    out = ROOT / "build/verification/tl_credit_reduction" / a.label
    out.mkdir(parents=True, exist_ok=False)
    source = a.replace.resolve() if a.replace else ROOT / "rtl/tl/tl_credit_admission.v"
    original = subprocess.check_output(["git", "show", a.reference_commit + ":rtl/tl/tl_credit_admission.v"], cwd=ROOT)
    reference = subprocess.check_output(["git", "rev-parse", a.reference_commit + "^{commit}"], cwd=ROOT, text=True).strip()
    original_meta = {"commit": reference, "sha256": hashlib.sha256(original).hexdigest()}
    cache_legacy_reference(out.parent, reference, original)
    (out / "original.json").write_text(json.dumps(original_meta, indent=2) + "\n")
    (out / "runner.py").write_bytes(Path(__file__).read_bytes())
    gold = out / "original.v"
    gate = out / "candidate.v"
    gold.write_bytes(original)
    gate.write_bytes(source.read_bytes())
    deps = [ROOT / "rtl/tl" / n for n in ("tl_control_decode.v", "tl_control_tenure.v")]
    result = {"complete": False, "all_passed": False, "reference_commit": reference,
              "original_sha256": hashlib.sha256(original).hexdigest(),
              "sources": {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in [source, *deps]},
              "output_bits": 123, "protocol_assumptions": [], "cut_inputs": [], "binary_logic": True,
              "proof_structure": "20 unconditional six-bit slot lemmas, then three flags conditional only on those discharged equalities", "results": []}

    def save():
        (out / "results.json").write_text(json.dumps(result, indent=2) + "\n")

    save()
    for width in a.widths:
        script = ""
        for name, rtl in (("gold", gold), ("gate", gate)):
            script += "read_verilog " + " ".join('"' + str(f) + '"' for f in [rtl, *deps]) + "\n"
            script += f"chparam -set WIDTH {width} tl_credit_admission\nprep -flatten -top tl_credit_admission\nrename -top {name}\n"
            if name == "gold":
                script += "design -stash original\n"
        wrapper = out / f"miter{width}.sv"
        ports = "input wire i_rstn,i_control,i_done,i_shared,input wire [255:0] i_half," + f"input wire [{20*(width+1)-1}:0] i_available,i_capacity,"
        ports += "output wire requirements_equal," + ",".join(f"output wire compare{j}" for j in range(23))
        body = "module admission_miter(" + ports + ");\nwire [119:0] gold_need,gate_need;wire [2:0] gold_flags,gate_flags;\n"
        for name in ("gold", "gate"):
            body += f"{name} {name}_inst(.i_rstn(i_rstn),.i_control(i_control),.i_done(i_done),.i_shared(i_shared),.i_half(i_half),.i_available(i_available),.i_capacity(i_capacity),.o_requirements({name}_need),.o_allow({name}_flags[0]),.o_wait({name}_flags[1]),.o_shortfall({name}_flags[2]));\n"
        body += "assign requirements_equal = gold_need==gate_need;\n"
        for j in range(23):
            body += (f"assign compare{j}=gold_need[{j*6}+:6]==gate_need[{j*6}+:6];\n" if j < 20 else
                     f"assign compare{j}=gold_flags[{j-20}]==gate_flags[{j-20}];\n")
        wrapper.write_text(body + "endmodule\n")
        script += f'design -copy-from original gold\nread_verilog "{wrapper}"\nprep -flatten -top admission_miter\nopt -full\ntechmap\nopt -full\ndesign -save full\n'
        for j in range(23):
            script += f'design -load full\ndelete -output admission_miter/w:compare* admission_miter/w:requirements_equal\nexpose admission_miter/w:compare{j}\n'
            if j >= 20:
                script += 'expose admission_miter/w:requirements_equal\n'
            script += 'opt_clean -purge\ncheck -assert\n'
            lemma = ' -set requirements_equal 1' if j >= 20 else ''
            script += f'sat -verify -timeout 90 -prove compare{j} 1{lemma} admission_miter\n'
        path = out / f"width{width}.ys"
        path.write_text(script)
        with (out / f"width{width}.log").open("w") as log:
            try:
                code = subprocess.run(["yosys", "-Q", "-T", "-s", str(path)], cwd=ROOT,
                                      stdout=log, stderr=subprocess.STDOUT, timeout=2400).returncode
            except subprocess.TimeoutExpired:
                code = 124
        text = (out / f"width{width}.log").read_text()
        row = {"width": width, "exit": code, "proved_queries": text.count("SAT proof finished - no model found: SUCCESS!"), "passed": code == 0 and
               text.count("SAT proof finished - no model found: SUCCESS!")==23}
        result["results"].append(row)
        save()
        print(row, flush=True)
        if not row["passed"]:
            break
    result["complete"] = True
    result["all_passed"] = len(result["results"])==len(a.widths) and all(r["passed"] for r in result["results"])
    save()
    return 0 if result["all_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

"""Run: python3 verification/tl_credit_reduction/run_formal_faults.py [--capture-existing].

Requires static_reduction_checks from the admission fault runner. Outputs three real
formal mismatches and concrete Icarus replays under build/verification/tl_credit_reduction.
Next independently audit all positive lemmas and these negative proof/RTL witnesses.
--capture-existing resumes only unchanged recorded failing proofs, without rerunning them.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
STAGE = ROOT / "build/verification/tl_credit_reduction"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(command, log):
    with log.open("w") as stream:
        return subprocess.run(command, cwd=ROOT, stdout=stream,
                              stderr=subprocess.STDOUT, timeout=300).returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-existing", action="store_true")
    args = parser.parse_args()
    result_path = STAGE / "formal_faults.json"
    if args.capture_existing and result_path.exists():
        backup = STAGE / "formal_faults_initial.json"
        if not backup.exists():
            backup.write_bytes(result_path.read_bytes())
    rows = []
    for name in ("lose_future_data", "no_shared_merge", "ignore_available"):
        label = "formal_" + name
        folder = STAGE / label
        mutant = ROOT / "build/verification/tl_credit_admission/static_reduction_checks" / name / "tl_credit_admission.v"
        if not args.capture_existing:
            require(not folder.exists(), "refusing to replace a recorded proof")
            code = run([sys.executable, "verification/tl_credit_reduction/run_equivalence.py",
                        "--widths", "8", "--label", label, "--replace", str(mutant)],
                       STAGE / (label + "_terminal.log"))
            require(code == 1, "expected an actual formal difference")
        proof = json.loads((folder / "results.json").read_text())
        require(proof["sources"][str(mutant)] == hashlib.sha256(mutant.read_bytes()).hexdigest(),
                "mutant changed since proof")
        require(len(proof["results"]) == 1 and proof["results"][0]["exit"] == 1,
                "missing terminal failing query")
        text = (folder / "width8.log").read_text()
        require("ERROR: Called with -verify and proof did fail!" in text and
                "time out" not in text, "compile/timeout is not a formal difference")
        query = proof["results"][0]["proved_queries"]
        require(query in (10, 20), "unexpected first failing output")
        parts = (folder / "width8.ys").read_text().split("design -load full\n")
        require(len(parts) == 24, "complete 23-query script required")
        replay = folder / "counterexample"
        replay.mkdir(exist_ok=args.capture_existing)
        witness = replay / "inputs.json"
        command = parts[query + 1].replace("sat -verify ", "sat ").replace(
            " admission_miter\n", f' -show-inputs -show-outputs -dump_json "{witness}" admission_miter\n')
        # Only the SAT command ends with the selected module; other transformations
        # retain the actual drivers and the already-discharged equality lemma.
        script = replay / "capture.ys"
        expected_script = parts[0] + "design -load full\n" + command
        if script.exists():
            require(args.capture_existing and script.read_text() == expected_script and witness.exists(),
                    "cannot resume changed or incomplete witness capture")
            code = 0
        else:
            script.write_text(expected_script)
            code = run(["yosys", "-Q", "-T", "-s", str(script)], replay / "capture.log")
        require(code == 0 and witness.exists() and "model found: FAIL!" in
                (replay / "capture.log").read_text(), "missing concrete SAT witness")
        signals = json.loads(witness.read_text())["signal"]
        values = {s["name"].lstrip("\\"): s["data"][0] if "data" in s else s["wave"][0]
                  for s in signals}
        widths = {"i_rstn": 1, "i_control": 1, "i_done": 1, "i_shared": 1,
                  "i_half": 256, "i_available": 180, "i_capacity": 180}
        inputs = {}
        for port, width in widths.items():
            bits = values[port]
            require(len(bits) == width and set(bits) <= set("01x"), "unexpected witness encoding")
            # SAT don't-care inputs get one explicit Boolean completion, then the
            # actual original/candidate RTL must reproduce the target mismatch.
            inputs[port] = int(bits.replace("x", "0"), 2)
        (replay / "concrete_inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
        gold = replay / "original.v"
        gate = replay / "candidate.v"
        gold.write_text((folder / "original.v").read_text().replace("module tl_credit_admission ", "module original_admission ", 1))
        gate.write_text((folder / "candidate.v").read_text().replace("module tl_credit_admission ", "module candidate_admission ", 1))
        body = "module tb; wire [122:0] original,candidate;\n"
        for module, prefix in (("original_admission", "original"), ("candidate_admission", "candidate")):
            ports = ",".join(f".{p}({w}'h{inputs[p]:x})" for p, w in widths.items())
            body += f"{module} #(.WIDTH(8)) {prefix}_inst({ports},.o_requirements({prefix}[119:0]),.o_allow({prefix}[120]),.o_wait({prefix}[121]),.o_shortfall({prefix}[122]));\n"
        start, size = (query * 6, 6) if query < 20 else (120 + query - 20, 1)
        body += f'''initial begin #1;
if ((^original===1'bx)||(^candidate===1'bx)) $fatal(1,"unknown concrete output");
if(original[{start}+:{size}]===candidate[{start}+:{size}]) $fatal(1,"SAT difference did not replay");
$display("PASS concrete formal fault {name} query={query}");$finish;end
endmodule
'''
        tb = replay / "tb.sv"
        tb.write_text(body)
        compile_code = run(["iverilog", "-g2012", "-s", "tb", "-o", str(replay / "sim.vvp"),
                            str(gold), str(gate), str(ROOT / "rtl/tl/tl_control_decode.v"),
                            str(ROOT / "rtl/tl/tl_control_tenure.v"), str(tb)], replay / "compile.log")
        require(compile_code == 0, "counterexample RTL compile failed")
        run_code = run(["vvp", str(replay / "sim.vvp")], replay / "run.log")
        require(run_code == 0 and "PASS concrete formal fault" in (replay / "run.log").read_text(),
                "counterexample RTL mismatch not reproduced")
        rows.append({"fault": name, "width": 8, "caught": True, "failed_query": query,
                     "proved_prior_queries": query, "capture_exit": code,
                     "compile_exit": compile_code, "replay_exit": run_code})
        result_path.write_text(json.dumps({"complete": len(rows) == 3, "results": rows}, indent=2) + "\n")
        print(rows[-1], flush=True)


if __name__ == "__main__":
    main()

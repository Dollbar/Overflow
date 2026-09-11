"""Run: python3 verification/rtl/burst_control_mutations.py --ports 4.

Output: retained isolated baseline/mutant sources, compile/simulation logs and
summary.json under build/burst_mutations_*. Next: inspect first divergences;
mutation detection is not functional coverage or complete protocol conformance.
Only disposable generated fixture copies are changed; product RTL is read-only.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import resource
import subprocess
import sys
import tempfile


MUTATIONS = {
    "first_credit_only": (
        "!(|(vc_threshold & ~selected_vc_capability)) && !(|(pool_threshold & ~pool_capability))",
        "((vc_threshold == 4'd0) || (|selected_vc_capability)) && ((pool_threshold == 4'd0) || (|pool_capability))"),
    "idle_phase_freeze": (
        "else if (reg_phase_known) reg_phase <=", "else if (reg_phase_known && o_req_valid) reg_phase <="),
    "wrong_offset": (
        "else if (new_data) cnt_offset <= 2'd1;", "else if (new_data) cnt_offset <= 2'd2;"),
    "wrong_last": (
        "assign data_last = cnt_offset == reg_last;", "assign data_last = cnt_offset != reg_last;"),
    "read_vc_pollution": (
        "{1'b1, C_PORT, reg_vc, reg_pools[cnt_offset]", "{1'b1, C_PORT, (reg_vc ^ i_candidate_vc), reg_pools[cnt_offset]"),
    "last_overlap": (
        "assign data_eligible = !reg_active &&", "assign data_eligible = (!reg_active || (tail_data && data_last)) &&"),
    "reset_keeps_active": (
        "if (!i_rstn) reg_active <= 1'b0;", "if (!i_rstn) reg_active <= reg_active;"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ports", type=int, choices=(2, 4), default=4)
    parser.add_argument("--verilator", default="verilator")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    source_path = root / "rtl/upli/upli_burst_control.v"
    source = source_path.read_text()
    identity = hashlib.sha256(source_path.read_bytes()).hexdigest()
    build = root / "build"
    build.mkdir(exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="burst_mutations_", dir=build))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    print(f"Mutation run: {run}", flush=True)
    vectors = run / "vectors.mem"
    with vectors.open("w") as output, (run / "oracle.log").open("w") as errors:
        subprocess.run([sys.executable, str(root / "verification/rtl/burst_control_vectors.py"),
                        "--ports", str(args.ports), "--credit-width", "4"],
                       stdout=output, stderr=errors, check=True)
    results = []
    for name, replacement in [("baseline", None), *MUTATIONS.items()]:
        candidate = run / name
        candidate.mkdir()
        content = source
        if replacement:
            old, new = replacement
            if source.count(old) != 1:
                raise ValueError(f"mutation {name} does not identify exactly one source occurrence")
            content = source.replace(old, new)
        rtl = candidate / "upli_burst_control.v"
        rtl.write_text(content)
        command = [args.verilator, "--binary", "--timing", "--language", "1364-2001", "-Wall",
                   "--top-module", "upli_burst_control_tb", "--Mdir", str(candidate / "obj"),
                   f"-GC_NUM_PORTS={args.ports}", "-GC_CREDIT_WIDTH=4", "-GC_HALF_PERIOD_PS=320",
                   str(rtl), str(root / "verification/rtl/upli_burst_control_tb.v")]
        with (candidate / "compile.log").open("w") as output:
            subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=True)
        with (candidate / "simulation.log").open("w") as output:
            status = subprocess.run([str(candidate / "obj/Vupli_burst_control_tb"), f"+VECTORS={vectors}"],
                                    stdout=output, stderr=subprocess.STDOUT, check=False).returncode
        text = (candidate / "simulation.log").read_text()
        divergence = re.search(r"^FAIL burst (pre|post|asynchronous state) row=(\d+)", text, re.MULTILINE)
        if name == "baseline":
            if status or "PASS burst_control " not in text or divergence:
                raise ValueError("unmodified same-configuration control failed")
        elif status == 0 or divergence is None or "PASS burst_control " in text:
            raise ValueError(f"{name} was not detected by an actual simulation comparison")
        results.append({"name": name, "exit_status": status,
                        "first_difference": divergence.group(1) if divergence else None,
                        "row": int(divergence.group(2)) if divergence else None,
                        "source_sha256": hashlib.sha256(rtl.read_bytes()).hexdigest()})
        print(json.dumps(results[-1]), flush=True)
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != identity:
        raise ValueError("product source changed while mutation controls ran")
    (run / "summary.json").write_text(json.dumps({"ports": args.ports, "credit_width": 4,
        "source_sha256": identity, "results": results}, indent=2) + "\n")
    print(f"PASS isolated mutation controls: {len(results)-1} detected; baseline passed", flush=True)


if __name__ == "__main__":
    main()

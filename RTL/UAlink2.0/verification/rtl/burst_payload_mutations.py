"""Run: python3 verification/rtl/burst_payload_mutations.py --ports 2.

Output: retained isolated baseline/mutant fixtures and summary.json under build.
Next: inspect first mismatches; this tests the testbench, not coverage closure.
Product RTL is read-only; only generated disposable fixture copies are changed.
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
    "wrong_tail_data": ("i_candidate_data[gen_tail*512 +: 512]", "i_candidate_data[(4-gen_tail)*512 +: 512]"),
    "read_overwrites_tail": (
        "o_candidate_accepted && i_candidate_has_data && (i_candidate_port == C_PORT)",
        "o_candidate_accepted && (i_candidate_port == C_PORT)"),
    "wrong_byte_enable": ("i_candidate_byte_enable[gen_tail*64 +: 64]", "~i_candidate_byte_enable[gen_tail*64 +: 64]"),
    "wrong_error": ("i_candidate_error[gen_tail]", "~i_candidate_error[gen_tail]"),
    "tail_not_debited": (".i_send_valid(o_data_valid),", ".i_send_valid(o_data_valid && (o_data_offset == 2'd0)),"),
    "request_lost": ("i_candidate_request & {C_REQUEST_WIDTH{o_req_valid}}", "i_candidate_request & {C_REQUEST_WIDTH{o_req_valid && !i_candidate_pool}}"),
    "sticky_lost": (
        "else if (o_req_credit_error || o_data_credit_error) reg_credit_error <= 1'b1;",
        "else reg_credit_error <= o_req_credit_error || o_data_credit_error;"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ports", type=int, choices=(1, 2, 4), default=2)
    parser.add_argument("--verilator", default="verilator")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    product = root / "rtl/upli/upli_burst_sender.v"
    source, identity = product.read_text(), hashlib.sha256(product.read_bytes()).hexdigest()
    run = Path(tempfile.mkdtemp(prefix="payload_mutations_", dir=root/"build"))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    print(f"Mutation run: {run}", flush=True)
    vectors = run / "vectors.mem"
    with vectors.open("w") as output, (run/"oracle.log").open("w") as errors:
        subprocess.run([sys.executable, str(root/"verification/rtl/burst_payload_vectors.py"),
                        "--ports", str(args.ports)], stdout=output, stderr=errors, check=True)
    results = []
    for name, replacement in [("baseline", None), *MUTATIONS.items()]:
        candidate = run/name
        candidate.mkdir()
        content = source
        if replacement:
            old, new = replacement
            if source.count(old) != 1:
                raise ValueError(f"mutation {name} must identify exactly one occurrence")
            content = source.replace(old, new)
        rtl = candidate/"upli_burst_sender.v"
        rtl.write_text(content)
        command = [args.verilator, "--binary", "--timing", "--language", "1364-2001", "-Wall",
                   "--top-module", "upli_burst_sender_tb", "--Mdir", str(candidate/"obj"),
                   f"-GC_NUM_PORTS={args.ports}", str(root/"rtl/upli/upli_credit_bank.v"),
                   str(root/"rtl/upli/upli_burst_control.v"), str(rtl),
                   str(root/"verification/rtl/upli_burst_sender_tb.v")]
        with (candidate/"compile.log").open("w") as output:
            subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=300)
        with (candidate/"simulation.log").open("w") as output:
            status = subprocess.run([str(candidate/"obj/Vupli_burst_sender_tb"), f"+VECTORS={vectors}"],
                                    stdout=output, stderr=subprocess.STDOUT, check=False, timeout=120).returncode
        text = (candidate/"simulation.log").read_text()
        mismatch = re.search(r"^FAIL payload (pre|post|asynchronous state|journal) row=(\d+)", text, re.MULTILINE)
        if name == "baseline":
            if status or "PASS burst_payload " not in text or mismatch:
                raise ValueError("unmodified same-configuration payload baseline failed")
        elif status == 0 or mismatch is None or "PASS burst_payload " in text:
            raise ValueError(f"{name} was not detected by actual behavioral comparison")
        item = {"name": name, "exit_status": status, "first_difference": mismatch.group(1) if mismatch else None,
                "row": int(mismatch.group(2)) if mismatch else None,
                "source_sha256": hashlib.sha256(rtl.read_bytes()).hexdigest()}
        results.append(item)
        print(json.dumps(item), flush=True)
    if identity != hashlib.sha256(product.read_bytes()).hexdigest():
        raise ValueError("product RTL changed during mutation controls")
    (run/"summary.json").write_text(json.dumps({"ports": args.ports, "source_sha256": identity,
                                               "results": results}, indent=2)+"\n")
    print(f"PASS payload mutations {len(results)-1} detected; baseline passed", flush=True)


if __name__ == "__main__":
    main()

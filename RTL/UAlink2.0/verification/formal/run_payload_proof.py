"""Prove one complete sender profile against independent ledgers and queues.

Run: python3 verification/formal/run_payload_proof.py --ports 4 --credit-width 16.
Outputs: source snapshot, full Yosys proof.log and summary.json under build.
Next: inspect both proof results; mapping/STA and connection FSM are separate.
The proof uses capacity4, request96, init2, connected inputs high. It includes
all payload bits and arbitrary native returns (including diagnostic errors).
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time


INPUTS = (
    "rtl/upli/upli_credit_bank.v",
    "rtl/upli/upli_burst_control.v",
    "rtl/upli/upli_burst_sender.v",
    "verification/formal/upli_payload_properties.v",
    "scripts/prove_burst_payload.tcl",
    "verification/formal/run_payload_proof.py",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ports", type=int, choices=(1, 2, 4), default=1)
    parser.add_argument("--credit-width", type=int, choices=range(3, 17), default=4)
    parser.add_argument("--yosys", default="yosys")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    (root/"build").mkdir(exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="payload_proof_", dir=root/"build"))
    identities = {}
    for name in INPUTS:
        identities[name] = hashlib.sha256((root/name).read_bytes()).hexdigest()
        destination = run/"snapshot"/name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root/name, destination)
    environment = dict(os.environ, UALINK_PORTS=str(args.ports),
                       UALINK_CREDIT_WIDTH=str(args.credit_width))
    command = [args.yosys, "-Q", "-T", "-c", "scripts/prove_burst_payload.tcl"]
    version = subprocess.check_output([args.yosys, "-V"], text=True).strip()
    started = time.monotonic()
    timeout = False
    with (run/"proof.log").open("w") as output:
        try:
            status = subprocess.run(command, cwd=run/"snapshot", env=environment,
                                    stdout=output, stderr=subprocess.STDOUT,
                                    timeout=600, check=False).returncode
        except subprocess.TimeoutExpired:
            status, timeout = None, True
    log = (run/"proof.log").read_text()
    solver_timeout = "proof did time out" in log
    unchanged = all(hashlib.sha256((root/n).read_bytes()).hexdigest() == h
                    for n, h in identities.items())
    proved_groups = [int(value) for value in re.findall(r"^PAYLOAD_GROUP_PROVED (\d+)$", log, re.MULTILINE)]
    group_count = 12+args.ports
    partition_union = log.count("PAYLOAD_PARTITION_UNION_PROVED\n") == 1
    reset_base = log.count("PAYLOAD_RESET_BASE_PROVED\n") == 1
    induction = (proved_groups == list(range(group_count))
                 and log.count(f"PAYLOAD_ALL_GROUPS_PROVED {group_count}\n") == 1)
    passed = (status == 0 and not timeout and not solver_timeout and unchanged
              and partition_union and reset_base and induction
              and log.count("SAT proof finished - no model found: SUCCESS!") == group_count+2
              and "ERROR:" not in log and "Warning:" not in log)
    summary = {
        "ports": args.ports, "credit_width": args.credit_width,
        "capacity": 4, "request_width": 96, "init_cycles": 2,
        "connected_inputs": True, "payload_symbolic_bits": 2048+256+4,
        "source_sha256": identities, "source_unchanged": unchanged,
        "tool": version, "command": command, "exit_status": status,
        "process_timeout": timeout, "solver_timeout": solver_timeout,
        "timeout": timeout or solver_timeout, "elapsed_seconds": time.monotonic()-started,
        "partition_union_proved": partition_union, "proved_groups": proved_groups,
        "reset_base_passed": reset_base, "induction_passed": induction,
        "passed": passed,
    }
    (run/"summary.json").write_text(json.dumps(summary, indent=2)+"\n")
    print(json.dumps({"directory": str(run.relative_to(root)), **summary}), flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()

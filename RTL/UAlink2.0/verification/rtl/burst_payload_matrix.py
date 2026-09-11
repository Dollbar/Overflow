"""Run: python3 verification/rtl/burst_payload_matrix.py --tag review --jobs 2.

Outputs: separate make logs, vectors/programs and a SHA-bound matrix JSON under
reports/build. Refuses an existing matrix log or summary. Next: inspect failures,
then independent proofs and actual whole-wrapper physical implementation.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess


SOURCES = (
    "rtl/upli/upli_burst_sender.v", "rtl/upli/upli_burst_control.v", "rtl/upli/upli_credit_bank.v",
    "config/upli_burst_sender_contract.json", "scripts/payload.mk",
    "verification/rtl/upli_burst_sender_tb.v", "verification/rtl/burst_payload_vectors.py",
    "verification/rtl/burst_payload_matrix.py", "model/ualink/upli_burst_payload.py",
    "model/ualink/upli_burst.py", "model/ualink/upli_burst_monitor.py",
    "model/ualink/upli_credit.py", "model/ualink/upli_connection.py",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--jobs", type=int, choices=range(1, 5), default=2)
    parser.add_argument("--verilator", default="verilator")
    args = parser.parse_args()
    if re.fullmatch(r"[A-Za-z0-9_]+", args.tag) is None:
        parser.error("tag must be nonempty alphanumeric/underscore")
    root = Path(__file__).resolve().parents[2]
    report = root / "reports" / f"burst_payload_matrix_{args.tag}.json"
    if report.exists():
        raise FileExistsError(report)
    cases = [(p, cw, 96, 2, half) for p in (1, 2, 4) for cw in (3, 4, 16)
             for half in (320, 3200)]
    cases += [(p, 4, rw, init, 320) for p in (1, 2, 4) for rw, init in ((1, 3), (129, 15))]
    identities = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in SOURCES}
    for case in cases:
        name = "_".join(map(str, case))
        log = root / "reports" / f"burst_payload_make_{name}_{args.tag}.log"
        if log.exists() or (root / "build" / f"burst_payload_{name}_{args.tag}").exists():
            raise FileExistsError(f"refuse overwriting retained run {name}")

    def run(case):
        ports, width, request, init, half = case
        name = "_".join(map(str, case))
        log = root / "reports" / f"burst_payload_make_{name}_{args.tag}.log"
        cmd = ["make", "--no-print-directory", "-f", str(root/"scripts/payload.mk"),
               "sim-burst-payload", f"PORTS={ports}", f"CREDIT_WIDTH={width}",
               f"REQUEST_WIDTH={request}", f"INIT_CYCLES={init}", f"HALF_PERIOD_PS={half}",
               f"TAG={args.tag}", f"VERILATOR={args.verilator}"]
        with log.open("x") as output:
            result = subprocess.run(cmd, cwd=root, stdout=output, stderr=subprocess.STDOUT,
                                    check=False, timeout=600)
        content = log.read_text()
        matches = re.findall(r"^PASS burst_payload (.+)$", content, re.MULTILINE)
        passed = result.returncode == 0 and len(matches) == 1 and "FAIL payload " not in content
        item = {"ports": ports, "credit_width": width, "request_width": request,
                "init_cycles": init, "period_ps": half*2, "exit_status": result.returncode,
                "passed": passed, "log": str(log.relative_to(root)),
                "metrics": {key: int(value) for key, value in re.findall(r"(\w+)=(\d+)", matches[0])}
                if len(matches) == 1 else {}}
        print(json.dumps(item), flush=True)
        return item

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(run, cases))
    if identities != {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in SOURCES}:
        raise RuntimeError("source changed during matrix; no current-source completion claimed")
    summary = {"scope": "normal_staged_sender_and_idle_credit_diagnostics_only",
               "sources": identities, "cases": results,
               "all_passed": all(item["passed"] for item in results)}
    with report.open("x") as output:
        json.dump(summary, output, indent=2)
        output.write("\n")
    if not summary["all_passed"]:
        raise SystemExit("FAIL payload matrix; inspect per-case logs")
    print(f"PASS payload matrix {len(results)} configurations", flush=True)


if __name__ == "__main__":
    main()

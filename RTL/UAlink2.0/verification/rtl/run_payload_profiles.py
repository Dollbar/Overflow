"""Run: python3 verification/rtl/run_payload_profiles.py --ports 4 --credit-width 16.

Outputs: uniquely retained build/payload_profiles_* vectors, compile/sim logs and
summary.json. Next: independent proof and actual mapped physical implementation.
This runner compares exact real activity with the independent scenario oracle;
zero-capacity profiles must transmit nothing, rather than pass on empty vectors.
"""

import argparse
from contextlib import redirect_stdout, redirect_stderr
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from verification.rtl.payload_profile_vectors import capacities, generate
from model.ualink.upli_credit import Account


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ports", type=int, choices=(1, 2, 4), default=1)
    parser.add_argument("--credit-width", type=int, choices=range(3, 17), default=4)
    parser.add_argument("--kind", choices=("mixed", "zero"), default="mixed")
    parser.add_argument("--init-cycles", type=int, choices=range(2, 16), default=2)
    parser.add_argument("--verilator", default="verilator")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    sources = [root/"rtl/upli"/name for name in
               ("upli_credit_bank.v", "upli_burst_control.v", "upli_burst_sender.v")]
    sources += [root/"verification/rtl/upli_burst_sender_tb.v"]
    inputs = sources+[root/"verification/rtl"/n for n in
                      ("burst_payload_vectors.py", "payload_profile_vectors.py", "run_payload_profiles.py")]
    inputs += [root/"model/ualink"/n for n in
               ("upli_burst_payload.py", "upli_burst.py", "upli_credit.py", "upli_connection.py", "upli_burst_monitor.py")]
    identity = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    (root/"build").mkdir(exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="payload_profiles_", dir=root/"build"))
    print(f"Profile run: {run}", flush=True)
    with (run/"vectors.mem").open("w") as vectors, (run/"oracle.log").open("w") as log:
        with redirect_stdout(vectors), redirect_stderr(log):
            expected = generate(args.ports, args.credit_width, args.kind, args.init_cycles)
    caps = capacities(args.ports, args.credit_width, args.kind)
    packed_caps = {}
    for channel in ("req", "orig_data"):
        packed_caps[channel] = sum(caps[Account(p, channel, vc)] << ((p*5+n)*args.credit_width)
                                   for p in range(args.ports) for n, vc in enumerate((0, 1, 2, 3, None)))
    bits = args.ports*5*args.credit_width
    minimum = 0 if args.kind == "zero" else 1
    cmd = [args.verilator, "--binary", "--timing", "--language", "1364-2001", "-Wall",
           "--top-module", "upli_burst_sender_tb", "--Mdir", str(run/"obj"),
           f"-GC_NUM_PORTS={args.ports}", f"-GC_CREDIT_WIDTH={args.credit_width}",
           f"-GC_INIT_CYCLES={args.init_cycles}",
           f"-GC_REQ_CAPACITIES={bits}'h{packed_caps['req']:x}",
           f"-GC_DATA_CAPACITIES={bits}'h{packed_caps['orig_data']:x}",
           "-GC_MIN_ROWS=20", f"-GC_MIN_REQUESTS={minimum}", f"-GC_MIN_BEATS={minimum}",
           f"-GC_MIN_OVERLAYS={minimum}", *map(str, sources)]
    (run/"command.json").write_text(json.dumps(cmd, indent=2)+"\n")
    with (run/"compile.log").open("w") as log:
        subprocess.run(cmd, cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=300)
    with (run/"simulation.log").open("w") as log:
        status = subprocess.run([str(run/"obj/Vupli_burst_sender_tb"), f"+VECTORS={run/'vectors.mem'}"],
                                stdout=log, stderr=subprocess.STDOUT, check=False, timeout=300).returncode
    content = (run/"simulation.log").read_text()
    match = re.search(r"^PASS burst_payload (.+)$", content, re.MULTILINE)
    if status or not match or "FAIL payload " in content:
        raise RuntimeError(f"actual profile simulation failed: {run}")
    actual = {key: int(value) for key, value in re.findall(r"(\w+)=(\d+)", match.group(1))}
    for key in ("rows", "requests", "data", "read_overlays"):
        assert actual[key] == expected[key], (key, actual, expected)
    assert actual["journal"] == expected["data"]
    assert identity == {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    result = {"source_sha256": identity, "scope": "actual_bank_capacity_and_split_init_functional_profile",
              "oracle": expected, "actual": actual, "passed": True,
              "capacity_bits": bits, "req_capacities_hex": f"{packed_caps['req']:x}",
              "data_capacities_hex": f"{packed_caps['orig_data']:x}"}
    (run/"summary.json").write_text(json.dumps(result, indent=2)+"\n")
    print(json.dumps({"directory": str(run.relative_to(root)), **expected, "passed": True}), flush=True)


if __name__ == "__main__":
    main()

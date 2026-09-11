"""Prove an actual mapped sender with complete-state binary comparisons.

Run: python3 verification/formal/run_payload_mapping.py --netlist MAPPED.v
     --liberty AUTHORIZED.lib --ports 4 --credit-width 16.
Outputs: snapshot, full proof.log and strict summary.json under build.
Next: all-corner STA on this exact netlist; no full-IP or analog claim.
Default capacity4; request96/init2 unless explicitly selected otherwise.
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


INPUTS = ("rtl/upli/upli_credit_bank.v", "rtl/upli/upli_burst_control.v",
          "rtl/upli/upli_burst_sender.v", "scripts/equiv_burst_sender.tcl",
          "verification/formal/run_payload_mapping.py")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--netlist", type=Path, required=True)
    parser.add_argument("--liberty", type=Path, required=True)
    parser.add_argument("--ports", type=int, choices=(1,2,4), required=True)
    parser.add_argument("--credit-width", type=int, choices=range(3,17), required=True)
    parser.add_argument("--request-width", type=int, default=96)
    parser.add_argument("--init-cycles", type=int, choices=range(2,16), default=2)
    parser.add_argument("--yosys", default="yosys")
    args = parser.parse_args()
    if not 1 <= args.request_width <= 1024:
        parser.error("request width must be in 1..1024")
    netlist, library = args.netlist.resolve(), args.liberty.resolve()
    if not netlist.is_file() or not library.is_file():
        parser.error("explicit existing mapped netlist and authorized Liberty required")
    root = Path(__file__).resolve().parents[2]
    (root/"build").mkdir(exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="payload_mapping_", dir=root/"build"))
    source_sha = {name:digest(root/name) for name in INPUTS}
    for name in INPUTS:
        target = run/"snapshot"/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root/name,target)
    external_sha = {"netlist":digest(netlist),"liberty":digest(library)}
    environment = dict(os.environ,UALINK_NETLIST=str(netlist),UALINK_LIBERTY=str(library),
        UALINK_PORTS=str(args.ports),UALINK_CREDIT_WIDTH=str(args.credit_width),
        UALINK_REQUEST_WIDTH=str(args.request_width),UALINK_INIT_CYCLES=str(args.init_cycles))
    version = subprocess.check_output([args.yosys,"-V"],text=True,timeout=20).strip()
    command = [args.yosys,"-Q","-T","-c","scripts/equiv_burst_sender.tcl"]
    started = time.monotonic()
    process_timeout = False
    with (run/"proof.log").open("w") as output:
        try:
            status = subprocess.run(command,cwd=run/"snapshot",env=environment,
                stdout=output,stderr=subprocess.STDOUT,timeout=2400,check=False).returncode
        except subprocess.TimeoutExpired:
            status, process_timeout = None, True
    content = (run/"proof.log").read_text()
    unchanged = (all(digest(root/n) == h and digest(run/"snapshot"/n) == h
                     for n,h in source_sha.items())
                 and digest(netlist) == external_sha["netlist"]
                 and digest(library) == external_sha["liberty"])
    solver_timeout = "proof did time out" in content
    count, comparisons = args.ports+2, 30+22*args.ports
    groups = [int(g) for g in re.findall(r"^PAYLOAD_MAPPING_GROUP_PROVED (\d+)$",content,re.M)]
    partition = content.count(f"PAYLOAD_MAPPING_PARTITION_PROVED comparisons={comparisons}\n") == 1
    reset = content.count("PAYLOAD_MAPPING_RESET_PROVED\n") == 1
    completion = content.count(f"PAYLOAD_MAPPING_PROVED groups={count} comparisons={comparisons}\n") == 1
    passed = (status == 0 and unchanged and not process_timeout and not solver_timeout
              and partition and reset and completion and groups == list(range(count))
              and content.count("SAT proof finished - no model found: SUCCESS!") == count+3
              and not re.search(r"^\s*(?:ERROR:|Warning:)",content,re.M))
    report = {"ports":args.ports,"credit_width":args.credit_width,"request_width":args.request_width,
        "init_cycles":args.init_cycles,"capacity":4,"binary_full_state":True,
        "source_sha256":source_sha,"external_sha256":external_sha,"inputs_unchanged":unchanged,
        "tool":version,"command":command,"exit_status":status,"process_timeout":process_timeout,
        "solver_budget_seconds":180,"process_budget_seconds":2400,
        "solver_timeout":solver_timeout,"timeout":process_timeout or solver_timeout,
        "elapsed_seconds":time.monotonic()-started,"comparisons":comparisons,
        "partition_union_passed":partition,"reset_base_passed":reset,"proved_groups":groups,
        "passed":bool(passed)}
    (run/"summary.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps({"directory":str(run.relative_to(root)),**report}),flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

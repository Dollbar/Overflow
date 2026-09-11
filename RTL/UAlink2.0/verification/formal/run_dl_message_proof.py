"""Run complete DL message arbiter induction with retained exact inputs.

Run: python3 verification/formal/run_dl_message_proof.py [--yosys yosys]
Outputs: build/dl_message_proof_*/snapshot, proof.log and summary.json.
Next: mapped equality and actual multi-corner characterization of this RTL.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--yosys', default='yosys')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    names = ('rtl/dl/dl_message_arbiter.v', 'verification/formal/dl_message_properties.v',
             'scripts/prove_dl_message.tcl', 'verification/formal/run_dl_message_proof.py',
             'config/dl_message_arbiter_contract.json')
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    hashes = {name: sha(root/name) for name in names}
    (root/'build').mkdir(exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='dl_message_proof_', dir=root/'build'))
    for name in names:
        path = run/'snapshot'/name
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root/name, path)
    version = subprocess.check_output([args.yosys, '-V'], text=True, timeout=20).strip()
    command = [args.yosys, '-Q', '-T', '-c', 'scripts/prove_dl_message.tcl']
    start = time.monotonic()
    timed_out = False
    with (run/'proof.log').open('w') as log:
        try:
            status = subprocess.run(command, cwd=run/'snapshot', stdout=log,
                                    stderr=subprocess.STDOUT, timeout=240).returncode
        except subprocess.TimeoutExpired:
            status, timed_out = 124, True
    content = (run/'proof.log').read_text()
    unchanged = all(sha(root/name) == sha(run/'snapshot'/name) == value
                    for name, value in hashes.items())
    reset = content.count('DL_MESSAGE_RESET_BASE_PROVED\n') == 1
    induction = content.count('DL_MESSAGE_FULL_INDUCTION_PROVED\n') == 1
    completion = content.count('DL_MESSAGE_FUNCTIONAL_PROVED groups=6\n') == 1
    solver_timeout = 'proof did time out' in content
    diagnostics = bool(re.search(r'^\s*(?:Warning:|ERROR:)', content, re.M))
    passed = (status == 0 and unchanged and not timed_out and not solver_timeout
              and not diagnostics and reset and induction and completion
              and content.count('SAT proof finished - no model found: SUCCESS!') == 2)
    record = {'directory': str(run.relative_to(root)), 'source_sha256': hashes,
              'tool': version, 'command': command, 'exit_status': status,
              'process_timeout': timed_out, 'solver_timeout': solver_timeout,
              'reset_base_passed': reset, 'full_induction_passed': induction,
              'source_unchanged': unchanged, 'passed': bool(passed),
              'proof_log_sha256': sha(run/'proof.log'),
              'elapsed_seconds': time.monotonic()-start,
              'scope': 'binary functional induction over arbitrary inputs; no source FIFO, PHY or wall-time liveness proof'}
    (run/'summary.json').write_text(json.dumps(record, indent=2)+'\n')
    print(json.dumps(record), flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())

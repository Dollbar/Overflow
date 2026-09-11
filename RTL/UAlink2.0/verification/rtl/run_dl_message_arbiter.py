"""Run exact, retained DL message arbiter simulation against independent vectors.

Run: python3 verification/rtl/run_dl_message_arbiter.py --seed 17 --cycles 4000
Outputs: fresh build/dl_message_*/snapshot, vectors, logs and summary.json.
Next: inspect scope/counters, then independent formal and physical checks.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed', type=int, default=17)
    parser.add_argument('--cycles', type=int, default=4000)
    parser.add_argument('--half-period-ps', type=int, choices=(320, 3200), default=320)
    parser.add_argument('--verilator', default='verilator')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    names = ('rtl/dl/dl_message_arbiter.v', 'verification/rtl/dl_message_arbiter_tb.v',
             'verification/rtl/dl_message_vectors.py',
             'verification/rtl/run_dl_message_arbiter.py',
             'model/ualink/dl_message_scheduler.py',
             'config/dl_message_arbiter_contract.json')
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    hashes = {name: sha(root/name) for name in names}
    (root/'build').mkdir(exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='dl_message_', dir=root/'build'))
    snapshot = run/'snapshot'
    for name in names:
        target = snapshot/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root/name, target)
    record = {'directory': str(run.relative_to(root)), 'source_sha256': hashes,
              'seed': args.seed, 'random_cycles': args.cycles,
              'period_ps': args.half_period_ps*2, 'stages': [], 'passed': False}
    start = time.monotonic()
    def invoke(command, log_name, timeout):
        with (run/log_name).open('w') as log:
            try:
                status = subprocess.run(command, cwd=snapshot, stdout=log,
                                        stderr=subprocess.STDOUT,
                                        timeout=timeout).returncode
            except subprocess.TimeoutExpired:
                status = 124
        record['stages'].append({'command': list(map(str, command)),
                                 'log': log_name, 'exit_status': status,
                                 'sha256': sha(run/log_name)})
        if status:
            raise RuntimeError(f'{log_name} failed with exit {status}')
    try:
        invoke([sys.executable, 'verification/rtl/dl_message_vectors.py',
                '--output', str(run/'vectors.mem'), '--summary', str(run/'vectors.json'),
                '--seed', str(args.seed), '--cycles', str(args.cycles)], 'vectors.log', 60)
        expected = json.loads((run/'vectors.json').read_text())
        record['expected'] = expected
        record['vectors_sha256'] = sha(run/'vectors.mem')
        invoke([args.verilator, '--binary', '--timing', '--language', '1364-2001',
                '-Wall', '--top-module', 'dl_message_arbiter_tb', '--Mdir', str(run/'obj'),
                f'-GC_HALF_PERIOD_PS={args.half_period_ps}',
                'rtl/dl/dl_message_arbiter.v', 'verification/rtl/dl_message_arbiter_tb.v'],
               'compile.log', 180)
        invoke([str(run/'obj/Vdl_message_arbiter_tb'), f'+VECTORS={run}/vectors.mem'],
               'sim.log', 60)
        matches = re.findall(r'^PASS dl_message rows=(\d+) words=(\d+) messages=(\d+) errors=(\d+)$',
                             (run/'sim.log').read_text(), re.M)
        assert len(matches) == 1, 'missing or duplicate completion marker'
        observed = dict(zip(('rows', 'words', 'messages', 'errors'), map(int, matches[0])))
        assert all(observed[key] == expected[key] for key in observed), (observed, expected)
        assert expected['rows'] >= args.cycles and expected['words'] > 1000
        assert all(sha(root/name) == sha(snapshot/name) == value
                   for name, value in hashes.items()), 'source changed during run'
        record.update(observed=observed, source_unchanged=True, passed=True)
    except (RuntimeError, AssertionError, OSError) as error:
        record['failure'] = str(error)
    record['elapsed_seconds'] = time.monotonic()-start
    (run/'summary.json').write_text(json.dumps(record, indent=2)+'\n')
    print(json.dumps(record), flush=True)
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

"""Run retained actual-cycle UART reset control checks with two independent references.

Run: python3 verification/rtl/run_uart_reset_control.py --period-ps 640 --depth 4 --seed 17
Outputs: fresh build/uart_reset_control_*/snapshot, exact vectors, logs and summary.json.
Next: inspect every event count, then perform independent proof and physical checks.
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

SOURCES = ('rtl/dl/dl_uart_reset_control.v', 'verification/rtl/uart_reset_control_tb.v',
           'verification/rtl/uart_reset_control_vectors.py',
           'verification/rtl/run_uart_reset_control.py',
           'model/ualink/uart_reset_control.py', 'model/ualink/uart_reset.py',
           'model/__init__.py', 'model/ualink/__init__.py',
           'config/uart_reset_control_contract.json')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--seed', type=int, default=17)
    p.add_argument('--cycles', type=int, default=4000)
    p.add_argument('--period-ps', type=int, default=640)
    p.add_argument('--depth', type=int, default=4)
    p.add_argument('--verilator', default='verilator')
    a = p.parse_args()
    if not 4 <= a.period_ps <= 1_000_000_000 or not 1 <= a.depth <= 16 or a.cycles < 1:
        p.error('TB requires period 4..1000000000ps, depth 1..16 and positive random cycles')
    root = Path(__file__).resolve().parents[2]
    hashes = {name: sha(root/name) for name in SOURCES}
    (root/'build').mkdir(exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='uart_reset_control_', dir=root/'build'))
    snapshot = run/'snapshot'
    for name in SOURCES:
        target = snapshot/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root/name, target)
    record = dict(directory=str(run.relative_to(root)), source_sha256=hashes,
                  seed=a.seed, random_cycles=a.cycles, period_ps=a.period_ps,
                  depth=a.depth, stages=[], passed=False, full_actual_clock=True,
                  references=['event_model_cycle_wrapper', 'absolute_time_upcount_ring_queue_scoreboard'])
    started = time.monotonic()

    def unchanged():
        assert all(sha(root/n) == sha(snapshot/n) == value for n, value in hashes.items()), 'source changed'

    def invoke(command, log_name, timeout):
        unchanged()
        with (run/log_name).open('w') as log:
            try:
                status = subprocess.run(command, cwd=snapshot, stdout=log,
                                        stderr=subprocess.STDOUT, timeout=timeout).returncode
            except subprocess.TimeoutExpired:
                status = 124
        record['stages'].append(dict(command=list(map(str, command)), log=log_name,
                                     exit_status=status, sha256=sha(run/log_name)))
        if status:
            raise RuntimeError(f'{log_name} failed with exit {status}')

    try:
        record['verilator'] = subprocess.check_output([a.verilator, '--version'], text=True, timeout=20).strip()
        invoke([sys.executable, 'verification/rtl/uart_reset_control_vectors.py',
                '--output', str(run/'vectors.mem'), '--summary', str(run/'vectors.json'),
                '--seed', str(a.seed), '--cycles', str(a.cycles),
                '--period-ps', str(a.period_ps), '--depth', str(a.depth)], 'vectors.log', 120)
        expected = json.loads((run/'vectors.json').read_text())
        record.update(expected=expected, vectors_sha256=sha(run/'vectors.mem'),
                      vectors_summary_sha256=sha(run/'vectors.json'))
        invoke([a.verilator, '--binary', '--timing', '--language', '1364-2001', '-Wall',
                '--top-module', 'uart_reset_control_tb', '--Mdir', str(run/'obj'),
                f'-GC_CLOCK_PERIOD_PS={a.period_ps}', f'-GC_RESPONSE_DEPTH={a.depth}',
                'rtl/dl/dl_uart_reset_control.v', 'verification/rtl/uart_reset_control_tb.v'],
               'compile.log', 180)
        invoke([str(run/'obj/Vuart_reset_control_tb'), f'+VECTORS={run}/vectors.mem'], 'sim.log', 240)
        keys = ('rows', 'edges', 'noops', 'requests', 'replies', 'starts', 'successes', 'retries', 'errors')
        pattern = '^PASS uart_reset_control ' + ' '.join(k+r'=(\d+)' for k in keys) + '$'
        matches = re.findall(pattern, (run/'sim.log').read_text(), re.M)
        assert len(matches) == 1, 'missing or duplicate completion marker'
        observed = dict(zip(keys, map(int, matches[0]), strict=True))
        assert all(observed[k] == expected[k] for k in keys), (observed, expected)
        assert observed['edges'] >= 2*expected['wait_cycles'] + a.cycles
        assert expected['output_bits'] == 56 and expected['compressed_storage_only'] is True
        unchanged()
        record.update(observed=observed, source_unchanged=True, passed=True)
    except (RuntimeError, AssertionError, OSError, subprocess.SubprocessError, ValueError) as error:
        record['failure'] = str(error)
    record['elapsed_seconds'] = time.monotonic()-started
    (run/'summary.json').write_text(json.dumps(record, indent=2)+'\n')
    print(json.dumps(record), flush=True)
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

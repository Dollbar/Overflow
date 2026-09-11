#!/usr/bin/env python3
"""Verify independent Endpoint ownership capacities over the real two-endpoint link.

Run: python3 verification/endpoint_transaction/run_capacity_matrix.py --kd28-root PATH --label NEW
Outputs: build/verification/endpoint_transaction/NEW/summary.json plus NEW_* case snapshots.
Next: inspect any failing case before expanding transaction sizes or memory-slot width.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = (lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kd28-root', type=Path, required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', args.label):
        parser.error('safe fresh label required')
    cases = []
    for originator in (1, 2, 3, 4, 8):
        for completer in (1, 2, 3, 4):
            options = ['--originator-capacity', str(originator), '--completer-capacity', str(completer),
                       '--memory-latency', '400', '--check-completer-full',
                       '--bank-depth', '1' if completer % 2 else '3']
            if (originator + completer) % 2:
                options += ['--inject']
            cases.append((f'o{originator}_c{completer}', options))
    for name, options in [('default', []), ('default_recovery', ['--inject']),
                          ('default_minimum', ['--inject', '--bank-depth', '1']),
                          ('capacity_fault', ['--originator-capacity', '1', '--fault', 'capacity'])]:
        cases.append((name, options))
    for originator, completer in ((0, 4), (256, 4), (4, 0), (4, 5), (-1, 3)):
        name = f'invalid_o{originator}_c{completer}'.replace('-', 'minus')
        cases.append((name, ['--originator-capacity', str(originator), '--completer-capacity', str(completer), '--expect-config-error']))
    base = ROOT / 'build/verification/endpoint_transaction'
    stage = base / args.label
    if stage.exists() or any((base / (args.label + '_' + name)).exists() for name, _ in cases):
        parser.error('matrix and all case labels must be fresh')
    stage.mkdir(parents=True)
    def run(case):
        name, options = case
        label = args.label + '_' + name
        command = [sys.executable, str(ROOT / 'verification/endpoint_transaction/run_transactions.py'),
                   '--kd28-root', str(args.kd28_root.resolve()), '--label', label, *options]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=220)
        record = base / label / 'result.json'
        row = dict(name=name, command=command, exit=result.returncode, stdout=result.stdout, stderr=result.stderr,
                   passed=result.returncode == 0, record=str(record.relative_to(ROOT)))
        if record.exists():
            row['record_sha256'] = hashlib.sha256(record.read_bytes()).hexdigest()
            evidence = json.loads(record.read_text())
            row['passed'] = row['passed'] and evidence['passed']
            row['source_drift'] = [path for path, expected in evidence['sources'].items()
                                   if hashlib.sha256(Path(path).read_bytes()).hexdigest() != expected]
            row['passed'] = row['passed'] and not row['source_drift']
        else:
            row['passed'] = False
        print(name, 'PASS' if row['passed'] else 'FAIL', flush=True)
        return row
    with ThreadPoolExecutor(max_workers=2) as pool:
        rows = list(pool.map(run, cases))
    summary = dict(passed=all(row['passed'] for row in rows), cases=rows,
                   scope='RTL_SIM: 20 capacity pairs, 3 default regressions, one wiring fault and 5 invalid configurations; eight requests per endpoint',
                   runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    (stage / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    return 0 if summary['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

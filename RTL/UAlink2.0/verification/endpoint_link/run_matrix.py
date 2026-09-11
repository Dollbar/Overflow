"""Execute bounded integrated RTL matrix and actual connection fault challenges.
Run: python3 verification/endpoint_link/run_matrix.py --kd28-root PATH --label NAME
Outputs fresh NAME_* directories and NAME/summary.json under build/verification/endpoint_link.
Next: review the explicit unimplemented protocol boundaries in docs/endpoint_link_integration_review.md.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kd28-root', type=Path, required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', args.label):
        parser.error('label must be one safe directory name')
    out = ROOT / 'build/verification/endpoint_link' / args.label
    out.mkdir(parents=True, exist_ok=False)
    cases = [
        ('clean', []),
        ('recovery', ['--inject']),
        ('minimum', ['--inject', '--depth', '1', '--delay', '1']),
        ('shared', ['--inject', '--shared', '1']),
        ('auth', ['--inject', '--auth', '1', '--depth', '5', '--delay', '5']),
        ('auth_shared', ['--inject', '--auth', '1', '--shared', '1', '--depth', '5']),
        ('wrap', ['--inject', '--depth', '5', '--delay', '7', '--count', '160']),
    ]
    failures = {
        'replay_data': 'end-to-end missing/duplicate/corrupt TL payload',
        'tl_consume': 'TL/DL consume atomicity',
        'rx_duplicate': 'TL rejected DL accepted payload',
        'retire_data': 'actual 600-bit SRAM retirement',
    }
    cases += [(fault, ['--inject', '--fault', fault]) for fault in failures]
    rows = []
    for name, flags in cases:
        label = args.label + '_' + name
        command = [sys.executable, str(ROOT / 'verification/endpoint_link/run.py'), '--kd28-root', str(args.kd28_root), '--label', label] + flags
        with (out / (name + '.log')).open('w') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT, timeout=450)
        case_dir = out.parent / label
        record = json.loads((case_dir / 'record.json').read_text())
        fault = name in failures
        if fault:
            diagnostics = '\n'.join(p.read_text() for p in [case_dir / 'run.log', case_dir / 'audit.log'] if p.is_file())
            passed = result.returncode != 0 and record['compile_exit'] == 0 and failures[name] in diagnostics
        else:
            passed = result.returncode == 0 and record['passed']
        row = dict(case=name, directory=str(case_dir.relative_to(ROOT)), command=command, expected_fault=fault, passed=passed, record_sha256=hashlib.sha256((case_dir / 'record.json').read_bytes()).hexdigest())
        if not fault and passed:
            row['audit'] = json.loads((case_dir / 'audit.json').read_text())
        rows.append(row)
        print(json.dumps(dict(case=name, expected_fault=fault, passed=passed)), flush=True)
    summary = dict(passed=all(row['passed'] for row in rows), positive_cases=7, connection_fault_cases=4, evidence_layer='integrated_rtl', results=rows)
    (out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    return 0 if summary['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

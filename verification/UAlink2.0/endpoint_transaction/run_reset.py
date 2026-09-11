#!/usr/bin/env python3
"""Run actual Endpoint/Switch uniform synchronous-reset integration.
Run: python3 verification/endpoint_transaction/run_reset.py --label NEW --kd28-root PATH
Outputs: build/verification/endpoint_transaction/NEW/{result.json,stage_*/{source snapshots,compile.log,run.log}}.
Next: inspect each RESET_TARGET and recovered handshake trace; this is not independent LinkDown recovery.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = (lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--kd28-root', type=Path, required=True)
    parser.add_argument('--stage', type=int, choices=(1, 2, 3), help='Default: all three reset windows')
    parser.add_argument('--fault', choices=('memory_reset', 'endpoint_reset'))
    parser.add_argument('--bank-depth', type=int, default=3, choices=range(1, 17))
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', args.label):
        parser.error('safe fresh label required')
    if args.fault and args.stage is None:
        parser.error('fault requires explicit --stage (memory_reset is intended for stage 2)')
    dependency_root = args.kd28_root.resolve()
    manifest_path = ROOT / 'third_party/kd28_dependency.json'
    manifest = json.loads(manifest_path.read_text())
    dependencies = []
    for relative, expected_hash in manifest['functional_sources_sha256'].items():
        source = dependency_root / relative
        if sha(source) != expected_hash:
            raise ValueError('KD28 dependency hash mismatch: ' + relative)
        dependencies.append(source)
    sources = [ROOT / 'verification/pkg/ualink_test_pkg.sv', ROOT / 'simulator/vip/ualink_memory_vip.sv']
    sources += sorted((ROOT / 'rtl').rglob('*.v')) + dependencies
    tb = ROOT / 'verification/endpoint_transaction/reset_tb.sv'
    stage = ROOT / 'build/verification/endpoint_transaction' / args.label
    stage.mkdir(parents=True, exist_ok=False)
    copies = []
    for index, source in enumerate(sources):
        dest = stage / 'sources' / (str(index) + '_' + source.name)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, dest)
        copies.append(dest)
    shutil.copyfile(tb, stage / 'tb.sv')
    shutil.copyfile(Path(__file__), stage / 'runner.py')
    shutil.copyfile(manifest_path, stage / 'kd28_dependency.json')
    for source, copy in zip(sources, copies):
        if sha(source) != sha(copy):
            raise ValueError('source changed during snapshot: ' + str(source))
    result = {
        'passed': False, 'fault': args.fault, 'bank_depth': args.bank_depth,
        'scope': 'all Endpoints, Switch, memory VIPs and transport pipeline reset in one local epoch; explicit CRC status/local DL record',
        'sources': {str(path): sha(path) for path in sources + [tb, Path(__file__), manifest_path]},
        'source_order': list(map(str, sources)) + [str(tb)],
        'snapshot_sources': {str(source): str(copy.relative_to(stage)) for source, copy in zip(sources, copies)},
        'cases': [],
    }
    result['snapshot_sources'].update({str(tb): 'tb.sv', str(Path(__file__)): 'runner.py', str(manifest_path): 'kd28_dependency.json'})
    mutant = {None: 0, 'memory_reset': 1, 'endpoint_reset': 2}[args.fault]
    for reset_stage in ([args.stage] if args.stage else [1, 2, 3]):
        case_dir = stage / ('stage_' + str(reset_stage))
        case_dir.mkdir()
        command = ['iverilog', '-g2012', '-s', 'tb', f'-Ptb.RESET_STAGE={reset_stage}',
                   f'-Ptb.MUTANT={mutant}', f'-Ptb.BANK_DEPTH={args.bank_depth}',
                   '-o', str(case_dir / 'sim.vvp'), *map(str, copies), str(stage / 'tb.sv')]
        case = {'stage': reset_stage}
        for name, cmd in [('compile', command), ('run', ['vvp', str(case_dir / 'sim.vvp')])]:
            case[name + '_command'] = cmd
            with (case_dir / (name + '.log')).open('w') as log:
                try:
                    code = subprocess.run(cmd, cwd=case_dir, stdout=log, stderr=subprocess.STDOUT, timeout=180).returncode
                except subprocess.TimeoutExpired:
                    code = 124
            case[name + '_exit'] = code
            if name == 'compile' and code:
                break
        log = (case_dir / 'run.log').read_text() if (case_dir / 'run.log').exists() else ''
        if args.fault:
            diagnostic = {'memory_reset': 'RESET_OLD_MEMORY_RESULT', 'endpoint_reset': 'RESET_STATE_NOT_CLEARED'}[args.fault]
            case['expected_diagnostic'] = diagnostic
            case['passed'] = case.get('compile_exit') == 0 and case.get('run_exit') == 1 and diagnostic in log and 'RESET_TARGET' in log
        else:
            case['passed'] = case.get('compile_exit') == 0 and case.get('run_exit') == 0 and f'NETWORK_RESET_PASS stage={reset_stage}' in log and 'RESET_QUIET_PASS' in log
        result['cases'].append(case)
        print(json.dumps({k: v for k, v in case.items() if k in ('stage', 'passed', 'compile_exit', 'run_exit')}), flush=True)
    result['passed'] = all(case['passed'] for case in result['cases'])
    result['artifacts_sha256'] = {str(path.relative_to(stage)): sha(path) for path in stage.rglob('*') if path.is_file()}
    (stage / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

"""Map and prove one DL arbiter, then characterize the exact netlist.

Run: python3 verification/rtl/run_dl_message_physical.py --library-root /authorized/libs
     --sta /configured/bin/sta [--yosys yosys]
Outputs: retained source snapshot, mapped netlist, equivalence/STA/check logs and
summary.json under a fresh build/dl_message_physical_* directory.
Next: inspect all failures/paths before adopting physical results; no routed,
external source-memory or complete-IP timing is proved by this local matrix.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time


CORNERS = ('tt0p9v25c', 'ssg0p81v125c', 'ssg0p81vm40c', 'ffg0p99v125c', 'ffg0p99vm40c')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library-root', type=Path, required=True)
    parser.add_argument('--sta', required=True)
    parser.add_argument('--yosys', default='yosys')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    libraries = {corner: args.library_root.resolve()/f'tcbn28hpcplusbwp40p140{corner}.lib'
                 for corner in CORNERS}
    for path in libraries.values():
        if not path.is_file():
            parser.error(f'missing explicit authorized library: {path}')
    names = ('rtl/dl/dl_message_arbiter.v', 'config/dl_message_arbiter_contract.json',
             'scripts/map_dl_message_arbiter.tcl', 'scripts/burst_abc.constr',
             'scripts/equiv_dl_message_arbiter.tcl', 'scripts/sta_dl_message_arbiter.tcl',
             'scripts/check_dl_message_sta_report.py', 'verification/rtl/run_dl_message_physical.py')
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    source_sha = {name: sha(root/name) for name in names}
    library_sha = {corner: sha(path) for corner, path in libraries.items()}
    (root/'build').mkdir(exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='dl_message_physical_', dir=root/'build'))
    snapshot = run/'snapshot'
    for name in names:
        path = snapshot/name
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root/name, path)
    record = {'directory': str(run.relative_to(root)), 'source_sha256': source_sha,
              'library_sha256': library_sha, 'mapping_corner': 'ssg0p81vm40c',
              'stages': [], 'sta_cases': [], 'passed': False,
              'equivalence_passed': False, 'all_corner_timing_passed': False,
              'yosys': subprocess.check_output([args.yosys, '-V'], text=True, timeout=20).strip(),
              'opensta': subprocess.check_output([args.sta, '-version'], text=True, timeout=20).strip(),
              'scope': 'local ideal-clock prelayout budgets; no external RAM, routing, PHY or ACK deadlines'}
    env = dict(os.environ, UALINK_LIBERTY=str(libraries['ssg0p81vm40c']),
               UALINK_BUILD_DIR=str(run/'mapped'), UALINK_NETLIST=str(run/'mapped/mapped.v'))
    started = time.monotonic()
    mapped_hash = None

    def check_inputs():
        assert all(sha(root/name) == sha(snapshot/name) == value for name, value in source_sha.items()), 'source changed'
        assert all(sha(libraries[corner]) == value for corner, value in library_sha.items()), 'library changed'
        if mapped_hash is not None:
            assert sha(run/'mapped/mapped.v') == mapped_hash, 'mapped netlist changed'

    def invoke(command, log_name, environment, timeout=240):
        check_inputs()
        with (run/log_name).open('w') as output:
            try:
                status = subprocess.run(command, cwd=snapshot, env=environment,
                                        stdout=output, stderr=subprocess.STDOUT,
                                        timeout=timeout).returncode
            except subprocess.TimeoutExpired:
                status = 124
        check_inputs()
        record['stages'].append({'command': list(map(str, command)), 'log': log_name,
                                 'exit_status': status, 'sha256': sha(run/log_name)})
        return status

    try:
        status = invoke([args.yosys, '-Q', '-T', '-c', 'scripts/map_dl_message_arbiter.tcl'], 'mapping.log', env)
        record['mapping_status'] = status
        assert status == 0, 'mapping failed'
        mapped_hash = sha(run/'mapped/mapped.v')
        record['mapped_sha256'] = mapped_hash
        record['mapped_json_sha256'] = sha(run/'mapped/mapped.json')
        areas = re.findall(r'"area":\s*([0-9.]+)', (run/'mapped/area.json').read_text())
        assert areas and all(value == areas[0] for value in areas), 'missing/ambiguous mapped area'
        record['area_um2'] = float(areas[0])
        status = invoke([args.yosys, '-Q', '-T', '-c', 'scripts/equiv_dl_message_arbiter.tcl'], 'equivalence.log', env)
        content = (run/'equivalence.log').read_text()
        record['equivalence_passed'] = (status == 0
            and content.count('DL_MESSAGE_MAPPING_RESET_PROVED\n') == 1
            and content.count('DL_MESSAGE_MAPPING_INDUCTION_PROVED\n') == 1
            and content.count('DL_MESSAGE_MAPPING_PROVED comparisons=17\n') == 1
            and content.count('SAT proof finished - no model found: SUCCESS!') == 2
            and not re.search(r'^\s*(?:Warning:|ERROR:)', content, re.M))
        assert record['equivalence_passed'], 'complete mapped equivalence failed'
        for corner in CORNERS:
            for period in ('0.640', '6.400'):
                log_name = f'sta_{corner}_{period}.log'
                sta_env = dict(env, UALINK_LIBERTY=str(libraries[corner]), UALINK_PERIOD_NS=period)
                status = invoke([args.sta, '-exit', 'scripts/sta_dl_message_arbiter.tcl'], log_name, sta_env, 60)
                check = invoke([sys.executable, 'scripts/check_dl_message_sta_report.py', str(run/log_name)],
                               f'check_{corner}_{period}.log', sta_env, 20)
                content = (run/log_name).read_text()
                case = {'corner': corner, 'period_ns': period, 'sta_status': status,
                        'check_status': check, 'passed': status == 0 and check == 0}
                for mode, key in (('max', 'setup_ns'), ('min', 'hold_ns')):
                    matches = re.findall(rf'^worst slack {mode}\s+(\S+)\s*$', content, re.M)
                    case[key] = float(matches[0]) if len(matches) == 1 else None
                record['sta_cases'].append(case)
        check_inputs()
        record['source_unchanged'] = True
        record['all_corner_timing_passed'] = len(record['sta_cases']) == 10 and all(case['passed'] for case in record['sta_cases'])
        record['passed'] = record['equivalence_passed'] and record['all_corner_timing_passed']
    except (OSError, AssertionError, ValueError) as error:
        record['failure'] = str(error)
    record['elapsed_seconds'] = time.monotonic()-started
    (run/'summary.json').write_text(json.dumps(record, indent=2)+'\n')
    print(json.dumps(record), flush=True)
    return 0 if record['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

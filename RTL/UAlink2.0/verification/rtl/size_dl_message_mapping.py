"""Bounded cell sizing with checked graph edits and complete revalidation.

Run: python3 verification/rtl/size_dl_message_mapping.py --project CANDIDATE
     --record PHYSICAL_RECORD.json --library-root /authorized/libs --sta /bin/sta
Outputs: build/dl_message_sizing_*/snapshots, changes.list, diagnostic.v,
checked mapped.v, complete equivalence/STA logs and summary.json.
Next: adopt only with exact functional source identity and all ten passing
timing cases. The OpenSTA diagnostic export is never the validated product.
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--record', type=Path, required=True)
    parser.add_argument('--library-root', type=Path, required=True)
    parser.add_argument('--sta', required=True)
    parser.add_argument('--yosys', default='yosys')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    project = args.project.resolve()
    original = json.loads(args.record.read_text())
    if not original['equivalence_passed'] or not original['source_unchanged']:
        parser.error('original actual mapping must already have verified identity and equivalence')
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    netlist = project/original['directory']/'mapped/mapped.v'
    assert sha(netlist) == original['mapped_sha256']
    assert all(sha(project/name) == value for name, value in original['source_sha256'].items())
    corners = ('tt0p9v25c', 'ssg0p81v125c', 'ssg0p81vm40c', 'ffg0p99v125c', 'ffg0p99vm40c')
    libraries = {c: args.library_root.resolve()/f'tcbn28hpcplusbwp40p140{c}.lib' for c in corners}
    assert all(sha(libraries[c]) == value for c, value in original['library_sha256'].items())
    own_names = ('scripts/size_dl_message_arbiter.tcl', 'scripts/apply_dl_message_sizing.tcl',
                 'verification/rtl/size_dl_message_mapping.py')
    own_sha = {name: sha(root/name) for name in own_names}
    run = Path(tempfile.mkdtemp(prefix='dl_message_sizing_', dir=root/'build'))
    snapshot = run/'snapshot'
    for origin, names in ((project, original['source_sha256']), (root, own_names)):
        for name in names:
            path = snapshot/name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(origin/name, path)
    record = {'directory': str(run.relative_to(root)), 'project': str(project.relative_to(root)),
              'source_sha256': original['source_sha256'], 'sizing_source_sha256': own_sha,
              'library_sha256': original['library_sha256'], 'original_mapped_sha256': sha(netlist),
              'original_physical_record_sha256': sha(args.record), 'stages': [], 'sta_cases': [],
              'equivalence_passed': False, 'all_corner_timing_passed': False, 'passed': False,
              'adopted': False}
    env = dict(os.environ, UALINK_NETLIST=str(netlist), UALINK_LIBERTY=str(libraries['ssg0p81vm40c']),
               UALINK_SIZE_OUT=str(run/'diagnostic.v'), UALINK_SIZE_CHANGES=str(run/'changes.list'))
    checked_hash = None
    generated_inputs = {}
    started = time.monotonic()

    def check_inputs():
        assert sha(netlist) == record['original_mapped_sha256']
        assert all(sha(project/name) == sha(snapshot/name) == value
                   for name, value in original['source_sha256'].items())
        assert all(sha(root/name) == sha(snapshot/name) == value for name, value in own_sha.items())
        assert all(sha(libraries[c]) == value for c, value in record['library_sha256'].items())
        assert all(sha(snapshot/name) == value for name, value in generated_inputs.items())
        if 'changes_sha256' in record:
            assert sha(run/'changes.list') == record['changes_sha256']
        if checked_hash is not None:
            assert sha(run/'mapped.v') == checked_hash

    def invoke(command, log_name, environment, timeout):
        check_inputs()
        with (run/log_name).open('w') as log:
            try:
                status = subprocess.run(command, cwd=snapshot, env=environment,
                                        stdout=log, stderr=subprocess.STDOUT, timeout=timeout).returncode
            except subprocess.TimeoutExpired:
                status = 124
        check_inputs()
        record['stages'].append({'command': list(map(str, command)), 'log': log_name,
                                 'exit_status': status, 'sha256': sha(run/log_name)})
        return status

    try:
        status = invoke([args.sta, '-exit', 'scripts/size_dl_message_arbiter.tcl'], 'sizing.log', env, 300)
        record['sizing_status'] = status
        assert status == 0, 'bounded sizing failed'
        record['changes_sha256'] = sha(run/'changes.list')
        # Paths are Tcl variables supplied through environment, not concatenated
        # into executable Tcl text; preserve spaces and avoid text injection.
        wrapper = snapshot/'scripts/emit_dl_message_sizing.tcl'
        wrapper.write_text('# Run: yosys -Q -T -c scripts/emit_dl_message_sizing.tcl with the\n'
                           '# UALINK_NETLIST, UALINK_LIBERTY, UALINK_SIZE_CHANGES, UALINK_SIZE_AREA,\n'
                           '# UALINK_SIZE_CHECKED and UALINK_SIZE_JSON variables supplied by the runner.\n'
                           '# Outputs: checked mapped netlist/JSON and area report.\n'
                           '# Next: full-state mapped proof and all ten STA cases.\n'
                           'source [file join [file dirname [info script]] apply_dl_message_sizing.tcl]\n'
                           'yosys hierarchy -check -top dl_message_arbiter\nyosys check -assert\n'
                           'yosys tee -o $env(UALINK_SIZE_AREA) stat -json -liberty $env(UALINK_LIBERTY)\n'
                           'yosys write_verilog -noattr -noexpr $env(UALINK_SIZE_CHECKED)\n'
                           'yosys write_json $env(UALINK_SIZE_JSON)\n')
        generated_inputs['scripts/emit_dl_message_sizing.tcl'] = sha(wrapper)
        apply_env = dict(env, UALINK_SIZE_AREA=str(run/'area.json'),
                         UALINK_SIZE_CHECKED=str(run/'mapped.v'), UALINK_SIZE_JSON=str(run/'mapped.json'))
        status = invoke([args.yosys, '-Q', '-T', '-c', 'scripts/emit_dl_message_sizing.tcl'], 'apply.log', apply_env, 90)
        assert status == 0, 'checked graph edit failed'
        checked_hash = sha(run/'mapped.v')
        record['mapped_sha256'] = checked_hash
        record['mapped_json_sha256'] = sha(run/'mapped.json')
        record['area_um2'] = float(re.findall(r'"area":\s*([0-9.]+)', (run/'area.json').read_text())[0])
        record['generated_apply_wrapper_sha256'] = sha(wrapper)
        checked_env = dict(env, UALINK_NETLIST=str(run/'mapped.v'))
        status = invoke([args.yosys, '-Q', '-T', '-c', 'scripts/equiv_dl_message_arbiter.tcl'], 'equivalence.log', checked_env, 240)
        text = (run/'equivalence.log').read_text()
        record['equivalence_passed'] = (status == 0
            and text.count('DL_MESSAGE_MAPPING_RESET_PROVED\n') == 1
            and text.count('DL_MESSAGE_MAPPING_INDUCTION_PROVED\n') == 1
            and text.count('DL_MESSAGE_MAPPING_PROVED comparisons=17\n') == 1
            and text.count('SAT proof finished - no model found: SUCCESS!') == 2
            and not re.search(r'^\s*(?:Warning:|ERROR:)', text, re.M))
        assert record['equivalence_passed'], 'complete checked mapped equivalence failed'
        for corner in corners:
            for period in ('0.640', '6.400'):
                log_name = f'sta_{corner}_{period}.log'
                case_env = dict(checked_env, UALINK_LIBERTY=str(libraries[corner]), UALINK_PERIOD_NS=period)
                status = invoke([args.sta, '-exit', 'scripts/sta_dl_message_arbiter.tcl'], log_name, case_env, 60)
                gate = invoke([sys.executable, 'scripts/check_dl_message_sta_report.py', str(run/log_name)],
                              f'check_{corner}_{period}.log', case_env, 20)
                text = (run/log_name).read_text()
                case = {'corner': corner, 'period_ns': period, 'sta_status': status,
                        'check_status': gate, 'passed': status == 0 and gate == 0}
                for mode, key in (('max', 'setup_ns'), ('min', 'hold_ns')):
                    matches = re.findall(rf'^worst slack {mode}\s+(\S+)\s*$', text, re.M)
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

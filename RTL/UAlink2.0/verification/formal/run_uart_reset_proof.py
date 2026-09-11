"""Run complete UART reset control state/output induction with retained exact inputs.

Run: python3 verification/formal/run_uart_reset_proof.py [--yosys yosys]
Outputs: build/uart_reset_proof_*/snapshot, proof.log and summary.json.
Next: mapped equality and actual multi-corner characterization of this RTL.
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


def audit_graph(path, contract_path):
    """Reject missing/disconnected actual state or reordered/missing public outputs."""
    try:
        raw = json.loads(path.read_text())['modules']['uart_reset_properties']
        nets = raw['netnames']; cells = raw['cells']
        names = ('sta_local', 'cnt_noops', 'cnt_wait', 'reg_local_all',
                 'cnt_response', 'reg_response_scope', 'reg_fault')
        state_bits = [b for n in names for b in nets['Reset_Inst.'+n]['bits']]
        assert len(state_bits) == len(set(state_bits)) == 43
        assert nets['observed_state']['bits'] == state_bits
        actual_cells = [c for c in cells.values() if c['type'] == '$dff'
                        and set(c['connections']['Q']).intersection(state_bits)]
        actual_q = [b for c in actual_cells for b in c['connections']['Q']]
        assert len(actual_cells) == 7 and len(actual_q) == 43 and set(actual_q) == set(state_bits)
        assert all(c['connections']['CLK'] == raw['ports']['i_clk']['bits']
                   and int(c['parameters']['CLK_POLARITY'], 2) == 1 for c in actual_cells)
        outputs = [p for p in json.loads(contract_path.read_text())['interfaces']['ports']
                   if p['direction'] == 'output']
        actual_outputs = [b for p in reversed(outputs) for b in nets['Reset_Inst.'+p['name']]['bits']]
        assert len(actual_outputs) == 56 and actual_outputs == nets['observed']['bits']
        groups = raw['ports']['o_groups']['bits']
        violation = raw['ports']['o_violation']['bits']
        assert len(groups) == 3 and all(type(b) is int for b in groups+violation)
        def driver(bits, operator):
            matches = [c for c in cells.values() if c['type'] == operator
                       and c['connections'].get('Y') == bits]
            assert len(matches) == 1, (bits, operator)
            return matches[0]['connections']
        assert driver(violation, '$reduce_or')['A'] == groups
        assert driver([groups[0]], '$logic_not')['A'] == nets['bounds_ok']['bits']
        assert driver([groups[1]], '$logic_not')['A'] == nets['state_ok']['bits']
        public_compare = driver([groups[2]], '$ne')
        assert public_compare['A'] == actual_outputs and public_compare['B'] == nets['expected']['bits']
        state_compare = driver(nets['state_ok']['bits'], '$eq')
        assert state_compare['A'] == state_bits and len(state_compare['B']) == 43
        assert all(type(b) is int for b in nets['bounds_ok']['bits'])
        assert len(raw['ports']) == 11 and sum(len(p['bits']) for p in raw['ports'].values() if p['direction']=='input') == 11
        assert not any(c['type'] in ('$assume', '$anyseq', '$anyconst') for c in cells.values())
        return dict(passed=True, actual_state_bits=43, actual_registers=7,
                    actual_outputs=15, actual_output_bits=56, nonclock_input_bits=10,
                    total_sequential_bits=sum(len(c['connections']['Q']) for c in cells.values() if c['type']=='$dff'),
                    connected_json_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    except (OSError, ValueError, KeyError, AssertionError) as e:
        return dict(passed=False, failure=type(e).__name__+': '+str(e))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--yosys', default='yosys')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    names = ('rtl/dl/dl_uart_reset_control.v', 'verification/formal/uart_reset_properties.v',
             'scripts/prove_uart_reset_control.tcl', 'verification/formal/run_uart_reset_proof.py',
             'config/uart_reset_control_contract.json')
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    hashes = {name: sha(root/name) for name in names}
    (root/'build').mkdir(exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='uart_reset_proof_', dir=root/'build'))
    for name in names:
        path = run/'snapshot'/name
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root/name, path)
    version = subprocess.check_output([args.yosys, '-V'], text=True, timeout=20).strip()
    command = [args.yosys, '-Q', '-T', '-c', 'scripts/prove_uart_reset_control.tcl']
    start = time.monotonic()
    timed_out = False
    with (run/'proof.log').open('w') as log:
        try:
            status = subprocess.run(command, cwd=run/'snapshot', stdout=log,
                                    env=dict(os.environ, UALINK_PROOF_DIR=str(run/'graph')),
                                    stderr=subprocess.STDOUT, timeout=300).returncode
        except subprocess.TimeoutExpired:
            status, timed_out = 124, True
    content = (run/'proof.log').read_text()
    unchanged = all(sha(root/name) == sha(run/'snapshot'/name) == value
                    for name, value in hashes.items())
    reset = content.count('UART_RESET_RESET_BASE_PROVED\n') == 1
    induction = content.count('UART_RESET_FULL_INDUCTION_PROVED\n') == 1
    completion = content.count('UART_RESET_FUNCTIONAL_PROVED groups=3 state_bits=43 output_bits=56\n') == 1
    solver_timeout = 'proof did time out' in content
    diagnostics = bool(re.search(r'^\s*(?:Warning:|ERROR:)', content, re.M))
    passed = (status == 0 and unchanged and not timed_out and not solver_timeout
              and not diagnostics and reset and induction and completion
              and content.count('SAT proof finished - no model found: SUCCESS!') == 2)
    audit = audit_graph(run/'graph/connected.json', root/'config/uart_reset_control_contract.json')
    passed = passed and audit['passed']
    record = {'state_output_audit': audit, 'directory': str(run.relative_to(root)), 'source_sha256': hashes,
              'tool': version, 'command': command, 'exit_status': status,
              'process_timeout': timed_out, 'solver_timeout': solver_timeout,
              'reset_base_passed': reset, 'full_induction_passed': induction,
              'source_unchanged': unchanged, 'passed': bool(passed),
              'proof_log_sha256': sha(run/'proof.log'),
              'elapsed_seconds': time.monotonic()-start,
              'scope': 'default640ps/depth4 binary induction over all10 nonclock input bits, complete43-bit actual state and56 output bits; arbitrary overload and illegal take; no environment liveness or integrated UART claim'}
    (run/'summary.json').write_text(json.dumps(record, indent=2)+'\n')
    print(json.dumps(record), flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())

"""Run python3 verification/tl_tx_qualification/run_structure.py --label NEW_LABEL.
Elaborates the actual packing core and audits its control/next-state input cones.
Outputs original graph, complete D/Q cut and source-bound structure result.
Next prove full standalone/integrated equivalence and measure actual top STA.
"""
from pathlib import Path
import argparse
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'verification/tl_partition_mapping'))
sys.path.insert(0, str(ROOT / 'verification/tl_prepared_partition'))
from run_cec import dump, execute, need, sha
from mapped_state import observe, audit_cut


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    need(args.label.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    stage = ROOT / 'build/verification/tl_tx_qualification' / args.label
    stage.mkdir(parents=True, exist_ok=False)
    source = ROOT / 'rtl/tl/tl_tx_packer_core.v'
    (stage / 'runner.py').write_bytes(Path(__file__).read_bytes())
    script = f'read_verilog "{source}"\nprep -top tl_tx_packer_core\ntechmap\nopt -full\ndffunmap\nopt_clean\ncheck -assert\nwrite_json "{stage}/original.json"\n'
    (stage / 'structure.ys').write_text(script)
    run = execute(['yosys', '-Q', '-T', '-s', str(stage / 'structure.ys')], stage / 'structure.log', 60)
    dump(stage / 'results.json', dict(complete=False, elaboration=run))
    need(run['exit'] == 0, 'packing core elaboration failed')
    graph = json.loads((stage / 'original.json').read_text())['modules']['tl_tx_packer_core']
    cut, layout = observe(graph, ['r_hold', 'r_prefer_fc'])
    need(audit_cut(graph, cut, layout) == 4, 'core state changed')
    dump(stage / 'cut.json', dict(modules={'step': cut}))
    dump(stage / 'state.json', layout)
    drivers = {}
    inputs = {}
    for name, port in cut['ports'].items():
        if port['direction'] == 'input':
            for bit in port['bits']:
                inputs[bit] = name
    for cell in cut['cells'].values():
        parents = [bit for port, bits in cell['connections'].items()
                   if cell['port_directions'][port] == 'input' for bit in bits]
        for port, bits in cell['connections'].items():
            if cell['port_directions'][port] == 'output':
                for bit in bits:
                    need(bit not in drivers, 'multiple control driver')
                    drivers[bit] = parents
    forbidden = {'i_header', 'i_tags', 'i_data0', 'i_data1', 'i_fc_flit'}
    roots = {}
    for name in ('o_valid', 'o_msg', 'o_header_taken', 'o_tags_taken', 'o_data_taken', 'o_fc_taken', 'n_state'):
        pending, seen, found = list(cut['ports'][name]['bits']), set(), set()
        while pending:
            bit = pending.pop()
            if bit in ('0', '1') or bit in seen:
                continue
            seen.add(bit)
            if bit in inputs:
                found.add(inputs[bit])
            else:
                need(bit in drivers, 'undriven control root')
                pending.extend(drivers[bit])
        need(not found.intersection(forbidden), 'raw payload reaches packing control: ' + name)
        roots[name] = sorted(found)
    result = dict(complete=True, source_sha256=sha(source), actual_state_bits=4,
                  original_clock=True, control_input_roots=roots, full_goal_complete=False)
    dump(stage / 'results.json', result)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

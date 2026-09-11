"""Run python3 verification/tl_tx_qualification/run_ready_identity.py --label NEW
[--ignore-held]. Prove the selected-ready identity on the actual channel RTL;
--ignore-held must expose a counterexample to ignoring a held class. Outputs
source snapshots, complete D/Q graphs, exact observations and SAT logs under
build/verification/tl_tx_qualification/NEW. Next perform full RTL equivalence
and actual process measurements before adopting the ready-path optimization.
"""
from pathlib import Path
import argparse
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'verification/tl_partition_mapping'))
sys.path.insert(0, str(ROOT / 'verification/tl_prepared_partition'))
from run_cec import dump, execute, need, sha
from mapped_state import observe, audit_cut


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--ignore-held', action='store_true')
    args = parser.parse_args()
    need(args.label.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    stage = ROOT / 'build/verification/tl_tx_qualification' / args.label
    stage.mkdir(parents=True, exist_ok=False)
    (stage / 'runner.py').write_bytes(Path(__file__).read_bytes())
    sources = []
    for name in ('tl_tx_channels', 'tl_tx_packer_core', 'tl_credit_admission', 'tl_control_decode', 'tl_control_tenure'):
        path = stage / (name + '.v')
        path.write_bytes((ROOT / 'rtl/tl' / path.name).read_bytes())
        sources.append(path)
    result = dict(complete=False, expected_counterexample=args.ignore_held,
                  sources={str(p): sha(p) for p in sources}, results=[], full_goal_complete=False)
    for width in (8, 16):
        folder = stage / f'w{width}'
        folder.mkdir()
        script = '\n'.join(f'read_verilog "{p}"' for p in sources)
        script += f'\nchparam -set WIDTH {width} tl_tx_channels\nprep -top tl_tx_channels -flatten\ntechmap\nopt -full\ndffunmap\nopt_clean\ncheck -assert\nwrite_json "{folder}/original.json"\n'
        (folder / 'prepare.ys').write_text(script)
        prepared = execute(['yosys', '-Q', '-T', '-s', str(folder / 'prepare.ys')], folder / 'prepare.log', 120)
        need(prepared['exit'] == 0, 'actual channel elaboration failed')
        graph = json.loads((folder / 'original.json').read_text())['modules']['tl_tx_channels']
        qs = {c['connections']['Q'][0] for c in graph['cells'].values() if c['type'] == '$_DFF_P_'}
        fields = sorted(n for n, v in graph['netnames'].items() if re.search(r'(?:^|\.)r_', n)
                        and any(b in qs for b in v['bits']) and all(b in qs or b in ('0', '1') for b in v['bits']))
        cut, layout = observe(graph, fields)
        need(audit_cut(graph, cut, layout) == 8, 'actual channel state inventory changed')
        dump(folder / 'cut.json', dict(modules={'step': cut}))
        dump(folder / 'state.json', layout)
        observations = dict(ready='ready', selected='selected_class', held='r_hold_valid',
                            held_class='r_hold_class', actual='Packer_Inst.i_header_ready')
        for name, net in observations.items():
            bits = graph['netnames'][net]['bits']
            need(len(bits) == (2 if name == 'ready' else 1), 'observation width mismatch')
            need(name not in cut['ports'], 'observation collision')
            cut['ports'][name] = dict(direction='output', bits=bits)
        cut['attributes'].pop('top', None)
        dump(folder / 'observed.json', dict(modules={'step': cut}))
        dump(folder / 'observations.json', observations)
        inputs = {n: p for n, p in cut['ports'].items() if p['direction'] == 'input'}
        declarations = [f'input wire [{len(p["bits"])-1}:0] {n}' for n, p in inputs.items()]
        declarations.append('output wire o_bad')
        connections = [f'.{n}({n})' for n in inputs] + [f'.{n}({n})' for n in observations]
        formula = '(|ready)' if args.ignore_held else '(held ? ready[held_class] : (|ready))'
        wrapper = ['module identity(' + ',\n'.join(declarations) + ');',
                   'wire [1:0] ready;wire selected,held,held_class,actual;',
                   'step dut(' + ',\n'.join(connections) + ');',
                   f'assign o_bad=actual!={formula};', 'endmodule']
        (folder / 'identity.v').write_text('\n'.join(wrapper) + '\n')
        script = f'read_json "{folder}/observed.json"\nread_verilog "{folder}/identity.v"\nprep -top identity -flatten\nopt -full\ncheck -assert\nsat -prove o_bad 0 -verify -show ready -show selected -show held -show held_class -show actual -show o_bad -dump_json "{folder}/witness.json"\n'
        (folder / 'proof.ys').write_text(script)
        proof = execute(['stdbuf', '-oL', '-eL', 'yosys', '-Q', '-T', '-s', str(folder / 'proof.ys')], folder / 'proof.log', 120)
        message = 'SAT proof finished - model found: FAIL!' if args.ignore_held else 'SAT proof finished - no model found: SUCCESS!'
        passed = proof['exit'] == (1 if args.ignore_held else 0) and (folder / 'proof.log').read_text().count(message) == 1
        if args.ignore_held and passed:
            signals = {s['name']: s for s in json.loads((folder / 'witness.json').read_text())['signal']}
            need(signals['held']['wave'].startswith('1') and signals['o_bad']['wave'].startswith('1'), 'not an actual held-class counterexample')
            ready = int(signals['ready']['data'][0], 2)
            selected = int(signals['selected']['wave'][0])
            held_class = int(signals['held_class']['wave'][0])
            actual = int(signals['actual']['wave'][0])
            need(selected == held_class and actual == ((ready >> selected) & 1)
                 and actual != bool(ready), 'witness does not demonstrate the selected-ready mismatch')
        result['results'].append(dict(width=width, actual_state_bits=8, proof=proof, passed=passed))
        dump(stage / 'results.json', result)
        print(width, passed, proof, flush=True)
    result['complete'] = all(r['passed'] for r in result['results'])
    dump(stage / 'results.json', result)
    return 0 if result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

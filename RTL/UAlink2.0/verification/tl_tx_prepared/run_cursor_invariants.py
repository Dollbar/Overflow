"""Run python3 verification/tl_tx_prepared/run_cursor_invariants.py --label NEW_LABEL
[--pair mapped_pair] [--widths 8 16]. Outputs four actual-RTL single-step SAT proofs for the cursor
relation domain: cursor<=8 and unowned implies cursor=0. Initial establishment
comes from independent_reset; next combine with complete mapped CEC/dormant SAT.
"""
from pathlib import Path
import argparse
import json

from run_reset_state import ROOT, identifier, audit_cut, dump, execute, need, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--pair', default='mapped_pair')
    parser.add_argument('--widths', type=int, nargs='+', choices=(8, 16), default=[8, 16])
    args = parser.parse_args()
    need(args.label.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    need(args.pair.replace('_', '').replace('-', '').isalnum(), 'invalid pair label')
    need(len(args.widths) == len(set(args.widths)), 'duplicate widths')
    base = ROOT / 'build/verification/tl_tx_prepared'
    stage = base / args.label
    stage.mkdir(exist_ok=False)
    (stage / 'runner.py').write_bytes(Path(__file__).read_bytes())
    result = dict(complete=False, scope='actual RTL one-step closure of cursor<=8 and unowned implies cursor=0',
                  initial_reset_proof_required=True, pair=args.pair, results=[], mapped_equivalence=False, full_goal_complete=False)
    for width in args.widths:
        source = base / args.pair / f'w{width}'
        graph = json.loads((source / 'gold_cut.json').read_text())['modules']['step_gold']
        original = json.loads((source / 'gold_observed.json').read_text())['modules']['tl_tx_prepared']
        layout = json.loads((source / 'gold_state.json').read_text())
        audit_cut(original, graph, layout)
        for lane in (0, 1):
            folder = stage / f'w{width}_lane{lane}'
            folder.mkdir()
            prefix = f'gen_prepare[{lane}].Prepare_Inst.'
            cursor, owner = layout['aliases'][prefix + 'r_cursor'], layout['aliases'][prefix + 'r_owned']
            need(len(cursor) == 4 and len(owner) == 1 and all(type(x) is int for x in cursor + owner),
                 'actual cursor/ownership state required')
            ports = {n: p for n, p in graph['ports'].items() if p['direction'] == 'input'}
            declarations = [f'input wire [{len(p["bits"])-1}:0] {identifier(n)}' for n, p in ports.items()]
            declarations += ['output wire o_bad']
            connections = [f'.{identifier(n)}({identifier(n)})' for n in ports] + ['.n_state(next_state)']
            vector = lambda name: '{' + ','.join(f'{name}[{x}]' for x in reversed(cursor)) + '}'
            code = ['module cursor_step(' + ',\n'.join(declarations) + ');',
                    f'wire [{layout["state_bits"]-1}:0] next_state;',
                    'step_gold actual(' + ',\n'.join(connections) + ');',
                    f"wire valid_current;assign valid_current=({vector('s_state')}<=4'd8)&&"
                    f"(s_state[{owner[0]}]||({vector('s_state')}==4'd0));",
                    f"assign o_bad=valid_current&&(({vector('next_state')}>4'd8)||"
                    f"(!next_state[{owner[0]}]&&({vector('next_state')}!=4'd0)));", 'endmodule']
            (folder / 'cursor.v').write_text('\n'.join(code) + '\n')
            dump(folder / 'inventory.json', dict(cursor=cursor, owner=owner, source_hashes={n: sha(source / n) for n in
                                                                                         ('gold_cut.json', 'gold_state.json', 'gold_observed.json')}))
            script = f'read_json "{source}/gold_cut.json"\nread_verilog "{folder}/cursor.v"\nprep -top cursor_step -flatten\nopt -full\ncheck -assert\nwrite_json "{folder}/cursor.json"\nsat -prove o_bad 0 -verify -dump_json "{folder}/witness.json"\n'
            (folder / 'proof.ys').write_text(script)
            proof = execute(['yosys', '-Q', '-T', '-s', str(folder / 'proof.ys')], folder / 'proof.log', 120)
            passed = proof['exit'] == 0 and (folder / 'proof.log').read_text().count('SAT proof finished - no model found: SUCCESS!') == 1
            result['results'].append(dict(width=width, lane=lane, proof=proof, passed=passed))
            dump(stage / 'results.json', result)
            print(width, lane, passed, proof, flush=True)
    result['complete'] = len(result['results']) == 2 * len(args.widths) and all(r['passed'] for r in result['results'])
    dump(stage / 'results.json', result)
    return 0 if result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

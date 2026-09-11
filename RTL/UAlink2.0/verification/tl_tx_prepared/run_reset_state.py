"""Run python3 verification/tl_tx_prepared/run_reset_state.py --label NEW_LABEL
[--pair mapped_pair] [--widths 8 16]. Proves actual RTL and mapped reset D values
from arbitrary independent state and SRAM read inputs. Outputs source-bound
inventory, wrappers and four SAT logs. Next prove dormant/capture relation and
complete state/output CEC; reset alone is not mapped sequential equivalence.
"""
from pathlib import Path
import argparse
import json
import re
import sys

from run_encoding_cec import ROOT, identifier
sys.path.insert(0, str(ROOT / 'verification/tl_partition_mapping'))
sys.path.insert(0, str(ROOT / 'verification/tl_prepared_partition'))
from run_cec import dump, execute, need, sha
from mapped_state import audit_cut


def reset_inventory(layout, side):
    need(side in ('gold', 'gate'), 'unknown side')
    payload_names = {'r_application', 'r_auth', 'r_capacity', 'r_control', 'r_counts',
                     'r_error', 'r_shared', 'r_slots', 'r_starts', 'r_tags'}
    observed, dormant = {}, set()
    for field, bits in layout['aliases'].items():
        prepared = re.fullmatch(r'gen_prepare\[([01])\]\.Prepare_Inst\.(r_\w+)', field)
        if prepared and prepared[2] in payload_names:
            dormant.update(x for x in bits if type(x) is int)
            continue
        if field.startswith('gen_prepare['):
            need(prepared and prepared[2] in ('r_owned', 'r_cursor'), 'unknown preparation state')
        else:
            need(field.startswith('Buffered_Inst.'), 'unknown production state')
        if prepared and prepared[2] == 'r_cursor':
            need(len(bits) == (4 if side == 'gold' else 9), 'unexpected actual cursor width')
        for index, bit in enumerate(bits):
            value = int(field == 'Buffered_Inst.Channels_Inst.Packer_Inst.r_prefer_fc'
                        or bool(prepared and prepared[2] == 'r_cursor' and side == 'gate' and index == 0))
            if type(bit) is int:
                need(bit not in observed or observed[bit] == value, 'conflicting reset aliases')
                observed[bit] = value
            else:
                need(bit == str(value), 'reset constant differs')
    need(not set(observed).intersection(dormant), 'reset and dormant state overlap')
    need(set(observed) | dormant == set(range(layout['state_bits'])), 'incomplete reset/dormant inventory')
    return observed, sorted(dormant)


def reset_wrapper(side, graph, layout, observed):
    ports = {n: p for n, p in graph['ports'].items()
             if p['direction'] == 'input' and n != 'i_rstn'}
    declarations = [f'input wire [{len(p["bits"])-1}:0] {identifier(n)}' for n, p in ports.items()]
    declarations += ['output wire o_bad']
    code = ['module reset_step(' + ',\n'.join(declarations) + ');',
            f'wire [{layout["state_bits"]-1}:0] next_state;']
    connections = [f'.{identifier(n)}({identifier(n)})' for n in ports]
    connections += [".i_rstn(1'b0)", '.n_state(next_state)']
    code.append(f'step_{side} actual(' + ',\n'.join(connections) + ');')
    indices = sorted(observed)
    values = sum(observed[index] << offset for offset, index in enumerate(indices))
    actual = '{' + ','.join(f'next_state[{i}]' for i in reversed(indices)) + '}'
    code.append(f"assign o_bad=({actual}!={len(indices)}'h{values:x});")
    return '\n'.join(code + ['endmodule']) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--pair', default='mapped_pair')
    parser.add_argument('--widths', type=int, nargs='+', choices=(8, 16), default=[8, 16])
    args = parser.parse_args()
    for label in (args.label, args.pair):
        need(label.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    need(len(args.widths) == len(set(args.widths)), 'duplicate widths')
    base = ROOT / 'build/verification/tl_tx_prepared'
    stage = base / args.label
    stage.mkdir(exist_ok=False)
    (stage / 'runner.py').write_bytes(Path(__file__).read_bytes())
    result = dict(complete=False, scope='independent arbitrary-state one-edge reset establishment',
                  reset_input=0, results=[], dormant_payload_relation=False,
                  mapped_equivalence=False, actual_mapped_fault_qualified=False, full_goal_complete=False)
    for width in args.widths:
        source = base / args.pair / f'w{width}'
        for side in ('gold', 'gate'):
            folder = stage / f'w{width}_{side}'
            folder.mkdir()
            layout = json.loads((source / f'{side}_state.json').read_text())
            original = json.loads((source / f'{side}_observed.json').read_text())['modules']['tl_tx_prepared']
            graph = json.loads((source / f'{side}_cut.json').read_text())['modules'][f'step_{side}']
            audit_cut(original, graph, layout)
            observed, dormant = reset_inventory(layout, side)
            dump(folder / 'inventory.json', dict(observed=observed, dormant=dormant))
            (folder / 'reset.v').write_text(reset_wrapper(side, graph, layout, observed))
            script = f'read_json "{source}/{side}_cut.json"\nread_verilog "{folder}/reset.v"\nprep -top reset_step -flatten\nopt -full\ncheck -assert\nwrite_json "{folder}/reset.json"\nsat -prove o_bad 0 -verify -dump_json "{folder}/witness.json"\n'
            (folder / 'proof.ys').write_text(script)
            proof = execute(['yosys', '-Q', '-T', '-s', str(folder / 'proof.ys')], folder / 'proof.log', 120)
            passed = proof['exit'] == 0 and (folder / 'proof.log').read_text().count('SAT proof finished - no model found: SUCCESS!') == 1
            result['results'].append(dict(width=width, side=side, observed_state_bits=len(observed),
                                          independent_dormant_payload_bits=len(dormant), proof=proof, passed=passed,
                                          source_hashes={n: sha(source / n) for n in
                                                         (f'{side}_observed.json', f'{side}_cut.json', f'{side}_state.json')}))
            dump(stage / 'results.json', result)
            print(width, side, passed, proof, flush=True)
    result['complete'] = len(result['results']) == 2 * len(args.widths) and all(r['passed'] for r in result['results'])
    dump(stage / 'results.json', result)
    return 0 if result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

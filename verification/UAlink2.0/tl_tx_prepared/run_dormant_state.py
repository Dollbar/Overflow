"""Run python3 verification/tl_tx_prepared/run_dormant_state.py --label NEW_LABEL
[--pair mapped_pair] [--widths 8 16]. For each actual mapped preparation lane with owner=0 and reset
cursor, prove independent dormant payload cannot change any public/macro output
or nonpayload next state; on capture its next payload must also agree. Outputs
four actual D/Q miters and SAT logs. Next compose reset, cursor invariants and
complete conditional CEC, and qualify a real capture fault before signoff.
"""
from pathlib import Path
import argparse
import json

from run_reset_state import ROOT, identifier, reset_inventory, audit_cut, dump, execute, need, sha


def dormant_inventory(layout, lane):
    need(type(lane) is int and lane in (0, 1), 'invalid lane')
    reset, all_dormant = reset_inventory(layout, 'gate')
    prefix = f'gen_prepare[{lane}].Prepare_Inst.'
    lane_bits = {x for field, bits in layout['aliases'].items() if field.startswith(prefix)
                 for x in bits if type(x) is int}
    payload = sorted(lane_bits.intersection(all_dormant))
    fixed = {x: reset[x] for x in lane_bits.intersection(reset)}
    observed = sorted(set(range(layout['state_bits'])) - set(payload))
    need(payload and len(fixed) == 10 and sum(fixed.values()) == 1, 'incomplete owner/cursor constraint')
    return payload, fixed, observed


def dormant_wrapper(graph, layout, lane):
    payload, fixed, observed = dormant_inventory(layout, lane)
    ports = {n: p for n, p in graph['ports'].items() if p['direction'] == 'input' and n != 's_state'}
    outputs = {n: p for n, p in graph['ports'].items() if p['direction'] == 'output' and n != 'n_state'}
    size, count = layout['state_bits'], len(payload)
    declarations = [f'input wire [{len(p["bits"])-1}:0] {identifier(n)}' for n, p in ports.items()]
    declarations += [f'input wire [{size-1}:0] shared_state',
                     f'input wire [{count-1}:0] independent_left, independent_right', 'output wire o_bad']
    code = ['module dormant_step(' + ',\n'.join(declarations) + ');']
    for side in ('left', 'right'):
        code.append(f'wire [{size-1}:0] state_{side}, next_{side};')
        independent = {bit: offset for offset, bit in enumerate(payload)}
        for index in range(size):
            value = f"1'b{fixed[index]}" if index in fixed else (
                f'independent_{side}[{independent[index]}]' if index in independent else f'shared_state[{index}]')
            code.append(f'assign state_{side}[{index}]={value};')
        connections = [f'.{identifier(n)}({identifier(n)})' for n in ports]
        connections += [f'.s_state(state_{side})', f'.n_state(next_{side})']
        for number, (name, port) in enumerate(outputs.items()):
            code.append(f'wire [{len(port["bits"])-1}:0] out_{side}_{number};')
            connections.append(f'.{identifier(name)}(out_{side}_{number})')
        code.append('step_gate actual_' + side + '(' + ',\n'.join(connections) + ');')
    mismatch = [f'(out_left_{n}!=out_right_{n})' for n in range(len(outputs))]
    vector = lambda side, bits: '{' + ','.join(f'next_{side}[{i}]' for i in reversed(bits)) + '}'
    mismatch.append(f'({vector("left", observed)}!={vector("right", observed)})')
    owner = layout['aliases'][f'gen_prepare[{lane}].Prepare_Inst.r_owned']
    need(len(owner) == 1 and owner[0] in observed, 'actual ownership bit required')
    mismatch.append(f'((next_left[{owner[0]}]||next_right[{owner[0]}])&&'
                    f'({vector("left", payload)}!={vector("right", payload)}))')
    code.append('assign o_bad=' + '|\n'.join(mismatch) + ';')
    return '\n'.join(code + ['endmodule']) + '\n'


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
    result = dict(complete=False, scope='actual mapped one-lane dormant-payload noninterference and capture relation',
                  pair=args.pair, results=[], mapped_equivalence=False, actual_capture_fault_qualified=False, full_goal_complete=False)
    for width in args.widths:
        source = base / args.pair / f'w{width}'
        original = json.loads((source / 'gate_observed.json').read_text())['modules']['tl_tx_prepared']
        graph = json.loads((source / 'gate_cut.json').read_text())['modules']['step_gate']
        layout = json.loads((source / 'gate_state.json').read_text())
        audit_cut(original, graph, layout)
        hashes = {n: sha(source / n) for n in ('gate_observed.json', 'gate_cut.json', 'gate_state.json')}
        for lane in (0, 1):
            folder = stage / f'w{width}_lane{lane}'
            folder.mkdir()
            payload, fixed, observed = dormant_inventory(layout, lane)
            dump(folder / 'inventory.json', dict(independent_payload=payload, fixed_owner_cursor=fixed,
                                                observed_next_state=observed, public_macro_output_bits=4144))
            (folder / 'dormant.v').write_text(dormant_wrapper(graph, layout, lane))
            script = f'read_json "{source}/gate_cut.json"\nread_verilog "{folder}/dormant.v"\nprep -top dormant_step -flatten\nopt -full\ncheck -assert\nwrite_json "{folder}/dormant.json"\nsat -prove o_bad 0 -verify -dump_json "{folder}/witness.json"\n'
            (folder / 'proof.ys').write_text(script)
            proof = execute(['yosys', '-Q', '-T', '-s', str(folder / 'proof.ys')], folder / 'proof.log', 180)
            passed = proof['exit'] == 0 and (folder / 'proof.log').read_text().count('SAT proof finished - no model found: SUCCESS!') == 1
            result['results'].append(dict(width=width, lane=lane, source_hashes=hashes,
                                          independent_payload_bits=len(payload), proof=proof, passed=passed))
            dump(stage / 'results.json', result)
            print(width, lane, passed, proof, flush=True)
    result['complete'] = len(result['results']) == 2 * len(args.widths) and all(r['passed'] for r in result['results'])
    dump(stage / 'results.json', result)
    return 0 if result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

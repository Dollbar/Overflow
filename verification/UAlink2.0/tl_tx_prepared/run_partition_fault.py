"""Run python3 verification/tl_tx_prepared/run_partition_fault.py --label NEW_LABEL
[--pair mapped_pair] [--physical physical_baseline]
[--reset-fault actual_reset_fault] [--encoded encoded_step_techmapped]
[--widths 8 16]. Reuse the actual one-D-pin mutants from actual_reset_fault,
derive their encoded next state, and qualify the exact output-cone CEC path.
Outputs source-bound BLIF partitions and actual mismatch logs. Next finish the
healthy complete partition matrix and independent sequential proof audit.
"""
from pathlib import Path
import argparse
import json

from run_encoding_cec import ROOT, relation, wrapper, dump, execute, need, sha
from proof_partitions import Network, partition, audit_partition
from run_partitioned_cec import outcome


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--pair', default='mapped_pair')
    parser.add_argument('--physical', default='physical_baseline')
    parser.add_argument('--reset-fault', default='actual_reset_fault')
    parser.add_argument('--encoded', default='encoded_step_techmapped')
    parser.add_argument('--widths', type=int, nargs='+', choices=(8, 16), default=[8, 16])
    args = parser.parse_args()
    for label in (args.label, args.pair, args.physical, args.reset_fault, args.encoded):
        need(label.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    need(len(args.widths) == len(set(args.widths)), 'duplicate widths')
    base = ROOT / 'build/verification/tl_tx_prepared'
    stage = base / args.label
    stage.mkdir(exist_ok=False)
    (stage / 'runner.py').write_bytes(Path(__file__).read_bytes())
    result = dict(complete=False, scope='actual mapped reset-D mutant detected by exact partition CEC',
                  results=[], mapped_equivalence=False, full_goal_complete=False)
    for width in args.widths:
        source = base / args.reset_fault / f'w{width}'
        pair = base / args.pair / f'w{width}'
        folder = stage / f'w{width}'
        folder.mkdir()
        gold = json.loads((pair / 'gold_state.json').read_text())
        gate = json.loads((source / 'state.json').read_text())
        mapping_log = base / args.physical / f'w{width}/map.log'
        rel = relation(gold, gate, mapping_log.read_text())
        graph = json.loads((source / 'cut.json').read_text())['modules']['step_gate']
        (folder / 'gate.v').write_text(wrapper('gate', graph['ports'], gold, gate, rel))
        dump(folder / 'relation.json', rel)
        script = f'read_json "{source}/cut.json"\nread_verilog "{folder}/gate.v"\nprep -top case_gate -flatten\ntechmap\nopt -full\ncheck -assert\nwrite_blif "{folder}/gate_raw.blif"\n'
        (folder / 'prepare.ys').write_text(script)
        prepare = execute(['yosys', '-Q', '-T', '-s', str(folder / 'prepare.ys')], folder / 'prepare.log', 120)
        need(prepare['exit'] == 0, 'actual mutant encoded emission failed')
        healthy = base / args.encoded / f'w{width}/gold.blif'
        original = Network(healthy.read_text())
        mutant = Network((folder / 'gate_raw.blif').read_text())
        need(set(original.inputs) == set(mutant.inputs) and set(original.outputs) == set(mutant.outputs),
             'fault wrapper changed full interface')
        field = 'Buffered_Inst.Channels_Inst.Packer_Inst.r_prefer_fc'
        index = gate['aliases'][field]
        need(len(index) == 1, 'single actual reset-D observation required')
        outputs = [f'c_next[{index[0]}]']
        audits = {}
        for side, network in (('gold', original), ('gate', mutant)):
            text = partition(network, outputs)
            audits[side] = audit_partition(network, text, outputs)
            (folder / f'{side}.blif').write_text(text)
        dump(folder / 'audit.json', audits)
        command = f'cec -T 120 -v "{folder}/gold.blif" "{folder}/gate.blif"'
        (folder / 'command.txt').write_text(command + '\n')
        proof = execute(['stdbuf', '-oL', '-eL', 'yosys-abc', '-c', command], folder / 'cec.log', 150)
        status = outcome(proof, (folder / 'cec.log').read_text())
        result['results'].append(dict(width=width, outputs=outputs, prepare=prepare, proof=proof,
                                      status=status, detected=status == 'different',
                                      source_hashes={str(p): sha(p) for p in
                                                     (source / 'cut.json', source / 'state.json', source / 'mutation.json',
                                                      pair / 'gold_state.json', mapping_log, healthy)}))
        dump(stage / 'results.json', result)
        print(width, status, proof, flush=True)
    result['complete'] = len(result['results']) == len(args.widths) and all(r['detected'] for r in result['results'])
    dump(stage / 'results.json', result)
    return 0 if result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

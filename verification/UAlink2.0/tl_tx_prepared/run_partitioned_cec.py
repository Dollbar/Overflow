"""Run python3 verification/tl_tx_prepared/run_partitioned_cec.py --label NEW_LABEL
--widths 8 16 [--group-size 128] [--timeout 120] [--resume].
Outputs audited BLIF partitions, exact commands and per-part terminal evidence.
Next qualify actual mapped faults and establish reset/dormant-state relation;
complete conditional partitions alone are not full sequential equivalence.
"""
from pathlib import Path
import argparse
import json
import re
import sys

from proof_partitions import Network, partition, split_outputs, audit_coverage, audit_partition
from run_encoding_cec import ROOT

sys.path.insert(0, str(ROOT / 'verification/tl_partition_mapping'))
from run_cec import dump, execute, need, sha


def outcome(run, text):
    if run['exit'] == 124:
        return 'timeout'
    if run['exit'] != 0 or any(x in text.lower() for x in ('warning:', 'error:', 'reading network from file has failed')):
        return 'tool_error'
    matches = re.findall(r'^Networks are equivalent(?: after structural hashing)?\.', text, re.M)
    if len(matches) == 1 and 'Networks are NOT EQUIVALENT.' not in text:
        return 'equivalent'
    if 'Networks are NOT EQUIVALENT.' in text:
        return 'different'
    return 'unresolved'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--source', default='encoded_step_techmapped')
    parser.add_argument('--widths', type=int, nargs='+', choices=(8, 16), default=[8, 16])
    parser.add_argument('--group-size', type=int, default=128)
    parser.add_argument('--timeout', type=int, default=120)
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    for label in (args.label, args.source):
        need(label.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    need(args.group_size > 0 and args.timeout > 0, 'invalid proof limits')
    need(len(args.widths) == len(set(args.widths)), 'duplicate widths')
    base = ROOT / 'build/verification/tl_tx_prepared'
    stage = base / args.label
    settings = dict(source=args.source, widths=args.widths,
                    group_size=args.group_size, timeout=args.timeout)
    if args.resume:
        record = json.loads((stage / 'results.json').read_text())
        need(record['settings'] == settings, 'resume configuration changed')
        need(sha(stage / 'runner.py') == sha(Path(__file__)), 'resume runner changed')
        need(sha(stage / 'proof_partitions.py') == sha(Path(__file__).with_name('proof_partitions.py')),
             'resume partition helper changed')
    else:
        stage.mkdir(exist_ok=False)
        (stage / 'runner.py').write_bytes(Path(__file__).read_bytes())
        (stage / 'proof_partitions.py').write_bytes(Path(__file__).with_name('proof_partitions.py').read_bytes())
        record = dict(settings=settings, widths={}, complete=False,
                      scope='complete public/macro outputs and actual encoded next-state; both binary cursors 0..8',
                      reset_relation=False, dormant_relation=False,
                      actual_mapped_fault_qualified=False, mapped_equivalence=False, full_goal_complete=False)
        dump(stage / 'results.json', record)
    for width in args.widths:
        source, folder = base / args.source / f'w{width}', stage / f'w{width}'
        folder.mkdir(exist_ok=args.resume)
        sources = {n: sha(source / n) for n in ('gold.blif', 'gate.blif', 'gold_pruned.blif', 'gate_pruned.blif')}
        networks, whole_audit = {}, {}
        for side in ('gold', 'gate'):
            original = Network((source / f'{side}.blif').read_text())
            networks[side] = Network((source / f'{side}_pruned.blif').read_text())
            whole_audit[side] = audit_partition(original, networks[side], original.outputs)
        gold, gate = networks['gold'], networks['gate']
        need(set(gold.inputs) == set(gate.inputs) and set(gold.outputs) == set(gate.outputs),
             'complete common interface differs')
        parts = split_outputs(gold.outputs, args.group_size)
        audit_coverage(gold.outputs, parts)
        key = str(width)
        if key in record['widths']:
            row = record['widths'][key]
            need(row['sources'] == sources and row['parts'] == parts, 'resume source or coverage changed')
        else:
            row = dict(sources=sources, whole_cone_audit=whole_audit, parts=parts,
                       public_macro_output_bits=4144, encoded_next_state_bits=6254 if width == 8 else 6574,
                       results=[], complete=False)
            need(len(gold.outputs) == row['public_macro_output_bits'] + row['encoded_next_state_bits'],
                 'actual output/next-state inventory count changed')
            record['widths'][key] = row
            dump(stage / 'results.json', record)
        for index, outputs in enumerate(parts):
            name = f'part_{index:03d}'
            directory = folder / name
            if index < len(row['results']):
                previous = row['results'][index]
                need(previous['index'] == index, 'noncontiguous proof results')
                for artifact, digest in previous['artifacts'].items():
                    need(sha(directory / artifact) == digest, 'retained part evidence changed')
                need(outcome(previous['run'], (directory / 'cec.log').read_text()) == previous['status'],
                     'retained terminal status changed')
                continue
            directory.mkdir(exist_ok=False)
            audits = {}
            for side in ('gold', 'gate'):
                raw = partition(networks[side], outputs)
                audits[side] = audit_partition(networks[side], raw, outputs)
                (directory / f'{side}.blif').write_text(raw)
            dump(directory / 'audit.json', audits)
            command = f'cec -T {args.timeout} -v "{directory}/gold.blif" "{directory}/gate.blif"'
            (directory / 'command.txt').write_text(command + '\n')
            run = execute(['stdbuf', '-oL', '-eL', 'yosys-abc', '-c', command],
                          directory / 'cec.log', args.timeout + 30)
            status = outcome(run, (directory / 'cec.log').read_text())
            row['results'].append(dict(index=index, output_bits=len(outputs), run=run, status=status,
                                       artifacts={n: sha(directory / n) for n in
                                                  ('gold.blif', 'gate.blif', 'audit.json', 'command.txt', 'cec.log')}))
            dump(stage / 'results.json', record)
            print(width, name, status, round(run['seconds'], 3), flush=True)
        row['complete'] = len(row['results']) == len(parts) and all(r['status'] == 'equivalent' for r in row['results'])
        dump(stage / 'results.json', record)
    record['complete'] = len(record['widths']) == len(args.widths) and all(r['complete'] for r in record['widths'].values())
    dump(stage / 'results.json', record)
    return 0 if record['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

"""Run python3 verification/tl_tx_prepared/check_mapped_correspondence.py
[--prefix NAME] [--output PATH]. Audit complete actual output/next-state CEC, reset, cursor
closure, dormant payload and real mapped fault evidence. Writes evidence.json.
Next repair physical timing and continue full payload/final dual-IP obligations.
"""
from pathlib import Path
import argparse
import copy
import json

from run_encoding_cec import ROOT, relation, wrapper
from run_reset_state import reset_inventory, reset_wrapper, audit_cut, need, sha, dump, identifier
from run_dormant_state import dormant_inventory, dormant_wrapper
from proof_partitions import Network, audit_partition, audit_coverage
from run_partitioned_cec import outcome

BASE = ROOT / 'build/verification/tl_tx_prepared'

ROLE_SUFFIXES = {
    'physical_baseline': 'physical', 'mapped_pair': 'pair',
    'encoded_step_techmapped': 'encoded', 'explicit_wide_partition': 'partitions',
    'independent_reset': 'reset', 'cursor_relation': 'cursor',
    'dormant_capture': 'dormant', 'actual_reset_fault': 'reset_fault',
    'actual_capture_fault': 'capture_fault', 'actual_partition_fault': 'partition_fault',
}


def configure_stages(prefix):
    if prefix is None:
        return {role: role for role in ROLE_SUFFIXES}
    need(isinstance(prefix, str) and prefix.replace('_', '').replace('-', '').isalnum(),
         'invalid evidence prefix')
    return {role: prefix + '_' + suffix for role, suffix in ROLE_SUFFIXES.items()}


STAGES = configure_stages(None)


def stage(role):
    return BASE / STAGES[role]



def read(path):
    return json.loads(path.read_text())


def hashes(folder, entries):
    for name, digest in entries.items():
        path = Path(name)
        need(sha(path if path.is_absolute() else folder / path) == digest, 'changed evidence: ' + name)


def sat(folder, row, positive=True):
    scope = next((role for role, name in STAGES.items() if name == folder.parent.name), None)
    width = folder.name.split('_')[0]
    need(width in ('w8', 'w16'), 'unknown SAT width')
    if scope == 'independent_reset':
        side = folder.name.split('_')[1]
        need(side in ('gold', 'gate') and positive, 'wrong reset proof scope')
        source, stem, top, show = stage('mapped_pair') / f'{width}/{side}_cut.json', 'reset', 'reset_step', ''
    elif scope in ('dormant_capture', 'cursor_relation'):
        need(positive and folder.name.split('_')[1] in ('lane0', 'lane1'), 'wrong state proof scope')
        side = 'gate' if scope == 'dormant_capture' else 'gold'
        stem = 'dormant' if scope == 'dormant_capture' else 'cursor'
        source, top, show = stage('mapped_pair') / f'{width}/{side}_cut.json', stem + '_step', ''
    elif scope in ('actual_reset_fault', 'actual_capture_fault'):
        need(not positive, 'negative mapped proof required')
        source = folder / 'cut.json'
        stem = 'reset' if scope == 'actual_reset_fault' else 'dormant'
        top = stem + '_step'
        show = (' -show-inputs -show o_bad' if scope == 'actual_reset_fault' else
                ' -show i_rstn -show i_done -show i_source_valid -show independent_left -show independent_right -show next_left -show next_right -show o_bad')
    else:
        raise ValueError('unknown SAT proof scope')
    script = f'read_json "{source}"\nread_verilog "{folder}/{stem}.v"\nprep -top {top} -flatten\nopt -full\ncheck -assert\nwrite_json "{folder}/{stem}.json"\nsat -prove o_bad 0 -verify{show} -dump_json "{folder}/witness.json"\n'
    need((folder / 'proof.ys').read_text() == script, 'SAT command changed its actual obligation')
    expected = 'SAT proof finished - no model found: SUCCESS!' if positive else 'SAT proof finished - model found: FAIL!'
    log = (folder / 'proof.log').read_text()
    need(row['proof']['exit'] == (0 if positive else 1) and log.count(expected) == 1, 'SAT status/log mismatch')
    if not positive:
        need((folder / 'witness.json').is_file(), 'missing actual fault witness')


def audit_parts(row, networks, folder):
    parts = row['parts']
    audit_coverage(networks['gold'].outputs, parts)
    need(len(row['results']) == len(parts) and row['complete'], 'incomplete partition matrix')
    for index, (outputs, saved) in enumerate(zip(parts, row['results'])):
        need(saved['index'] == index and saved['output_bits'] == len(outputs), 'wrong part identity')
        part_folder = folder / f'part_{index:03d}'
        hashes(part_folder, saved['artifacts'])
        for side in ('gold', 'gate'):
            actual = (part_folder / f'{side}.blif').read_text()
            audit_partition(networks[side], actual, outputs)
        need(saved['status'] == 'equivalent' and outcome(saved['run'], (part_folder / 'cec.log').read_text()) == 'equivalent',
             'part did not prove equivalence')
        command = f'cec -T 120 -v "{part_folder}/gold.blif" "{part_folder}/gate.blif"\n'
        need((part_folder / 'command.txt').read_text() == command, 'unapproved CEC command')
    return len(parts)


def actual_pair(width):
    folder = stage('mapped_pair') / f'w{width}'
    layouts, graphs = {}, {}
    for side in ('gold', 'gate'):
        layouts[side] = read(folder / f'{side}_state.json')
        original = read(folder / f'{side}_observed.json')['modules']['tl_tx_prepared']
        graphs[side] = read(folder / f'{side}_cut.json')['modules']['step_' + side]
        audit_cut(original, graphs[side], layouts[side])
    return layouts, graphs


def cursor_text(graph, layout, lane):
    prefix = f'gen_prepare[{lane}].Prepare_Inst.'
    cursor, owner = layout['aliases'][prefix + 'r_cursor'], layout['aliases'][prefix + 'r_owned']
    ports = {n: p for n, p in graph['ports'].items() if p['direction'] == 'input'}
    declarations = [f'input wire [{len(p["bits"])-1}:0] {identifier(n)}' for n, p in ports.items()] + ['output wire o_bad']
    connections = [f'.{identifier(n)}({identifier(n)})' for n in ports] + ['.n_state(next_state)']
    vector = lambda name: '{' + ','.join(f'{name}[{x}]' for x in reversed(cursor)) + '}'
    return '\n'.join(['module cursor_step(' + ',\n'.join(declarations) + ');',
                      f'wire [{layout["state_bits"]-1}:0] next_state;', 'step_gold actual(' + ',\n'.join(connections) + ');',
                      f"wire valid_current;assign valid_current=({vector('s_state')}<=4'd8)&&(s_state[{owner[0]}]||({vector('s_state')}==4'd0));",
                      f"assign o_bad=valid_current&&(({vector('next_state')}>4'd8)||(!next_state[{owner[0]}]&&({vector('next_state')}!=4'd0)));", 'endmodule']) + '\n'


def audit_fault(label, width, healthy):
    folder = stage(label) / f'w{width}'
    record = read(stage(label) / 'results.json')
    row = next(r for r in record['results'] if r['width'] == width)
    need(record['complete'] and row['detected'] and row['prepare']['exit'] == 0, 'incomplete mapped fault')
    mutation = read(folder / 'mutation.json')
    source = stage('physical_baseline') / f'w{width}/mapped.json'
    need(sha(source) == mutation['source_sha256'], 'mapped mutant source changed')
    original = read(source)['modules']['tl_tx_prepared']
    changed = read(folder / 'mapped_fault.json')['modules']['tl_tx_prepared']
    cell = mutation['cell']
    need(original['cells'][cell] == mutation['before'] and changed['cells'][cell] == mutation['after'], 'actual mutation descriptor differs')
    expected = copy.deepcopy(original)
    target = expected['cells'][cell]
    need(target['type'] == 'DFQD2BWP40P140', 'fault is not an actual mapped FF')
    if label == 'actual_reset_fault':
        need(target['connections']['Q'] == original['netnames']['Buffered_Inst.Channels_Inst.Packer_Inst.r_prefer_fc']['bits'], 'wrong reset fault FF')
        target['connections']['D'] = original['ports']['i_done']['bits']
    else:
        control = original['netnames']['gen_prepare[0].Prepare_Inst.r_control']['bits']
        need(target['connections']['Q'] == [control[0]], 'wrong capture fault FF')
        target['connections']['D'] = [control[1]]
    need(expected == changed and changed != original, 'mutation changed more than the selected D connection')
    graph = read(folder / 'observed.json')['modules']['tl_tx_prepared']
    cut, layout = read(folder / 'cut.json')['modules']['step_gate'], read(folder / 'state.json')
    audit_cut(graph, cut, layout)
    need(layout['aliases'] == healthy['aliases'], 'actual fault changed state inventory')
    if label == 'actual_reset_fault':
        observed, _ = reset_inventory(layout, 'gate')
        need((folder / 'reset.v').read_text() == reset_wrapper('gate', cut, layout, observed), 'reset fault proof wrapper changed')
    else:
        need((folder / 'dormant.v').read_text() == dormant_wrapper(cut, layout, 0), 'capture fault proof wrapper changed')
    sat(folder, row, False)
    signals = {r['name']: r for r in read(folder / 'witness.json')['signal']}
    need(signals['o_bad']['wave'].startswith('1'), 'fault witness does not violate the obligation')
    if label == 'actual_reset_fault':
        need(signals['i_done']['wave'].startswith('0'), 'wrong reset-D witness')
    else:
        need(signals['i_rstn']['wave'].startswith('1') and signals['i_done']['wave'].startswith('1')
             and signals['i_source_valid']['data'][0][-1] == '1', 'fault witness is not an actual lane-0 capture')
        owner = layout['aliases']['gen_prepare[0].Prepare_Inst.r_owned'][0]
        control_bit = layout['aliases']['gen_prepare[0].Prepare_Inst.r_control'][0]
        left, right = [signals[n]['data'][0] for n in ('next_left', 'next_right')]
        need(left[-owner-1] == right[-owner-1] == '1' and left[-control_bit-1] != right[-control_bit-1],
             'capture witness does not expose the real payload-D fault')
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    STAGES.update(configure_stages(args.prefix))
    output = args.output or BASE / ((args.prefix + '_' if args.prefix else '') + 'mapped_correspondence_evidence.json')
    matrix = read(stage('explicit_wide_partition') / 'results.json')
    need(matrix['complete'] and set(matrix['widths']) == {'8', '16'}, 'complete two-width matrix required')
    reset, dormant, cursor = [read(stage(label) / 'results.json') for label in ('independent_reset', 'dormant_capture', 'cursor_relation')]
    for report in (reset, dormant, cursor):
        need(report['complete'] and len(report['results']) == 4 and all(r['passed'] for r in report['results']), 'incomplete sequential relation matrix')
    encoded = read(stage('encoded_step_techmapped') / 'results.json')
    pair_record = read(stage('mapped_pair') / 'results.json')
    hashes(ROOT, pair_record['sources'])
    need(sha(Path(pair_record['library']['path'])) == pair_record['library']['sha256'], 'actual mapped library changed')
    evidence = dict(complete=False, scope='binary post-reset actual standard-cell equivalence with common arbitrary SRAM read values',
                    stages=dict(STAGES), results=[], reset_queries=4, cursor_queries=4, dormant_queries=4,
                    actual_reset_faults=2, actual_capture_faults=2, actual_partition_faults=2,
                    mapped_equivalence=False, macro_signoff=False, full_goal_complete=False)
    for width in (8, 16):
        layouts, graphs = actual_pair(width)
        paired = next(r for r in pair_record['results'] if r['width'] == width)
        need(sha(stage('mapped_pair') / f'w{width}/mapped.v') == paired['netlist_sha256'] ==
             sha(stage('physical_baseline') / f'w{width}/mapped.v'), 'actual physical netlist identity changed')
        original_row = next(r for r in encoded['results'] if r['width'] == width)
        hashes(ROOT, original_row['sources'])
        codebook = relation(layouts['gold'], layouts['gate'], (stage('physical_baseline') / f'w{width}/map.log').read_text())
        networks = {}
        source = stage('encoded_step_techmapped') / f'w{width}'
        hashes(source, matrix['widths'][str(width)]['sources'])
        for side in ('gold', 'gate'):
            need((source / f'{side}.sv').read_text() == wrapper(side, graphs[side]['ports'], layouts['gold'], layouts['gate'], codebook),
                 'complete encoded wrapper changed')
            raw = Network((source / f'{side}.blif').read_text())
            networks[side] = Network((source / f'{side}_pruned.blif').read_text())
            audit_partition(raw, networks[side], raw.outputs)
            row = next(r for r in reset['results'] if r['width'] == width and r['side'] == side)
            folder = stage('independent_reset') / f'w{width}_{side}'
            hashes(stage('mapped_pair') / f'w{width}', row['source_hashes'])
            observed, excluded = reset_inventory(layouts[side], side)
            need(row['observed_state_bits'] == len(observed) and row['independent_dormant_payload_bits'] == len(excluded), 'reset coverage changed')
            need((folder / 'reset.v').read_text() == reset_wrapper(side, graphs[side], layouts[side], observed), 'reset wrapper changed')
            sat(folder, row)
        need(set(networks['gold'].inputs) == set(networks['gate'].inputs) and set(networks['gold'].outputs) == set(networks['gate'].outputs), 'full encoded interface mismatch')
        parts = audit_parts(matrix['widths'][str(width)], networks, stage('explicit_wide_partition') / f'w{width}')
        for lane in (0, 1):
            row = next(r for r in dormant['results'] if r['width'] == width and r['lane'] == lane)
            folder = stage('dormant_capture') / f'w{width}_lane{lane}'
            hashes(stage('mapped_pair') / f'w{width}', row['source_hashes'])
            need((folder / 'dormant.v').read_text() == dormant_wrapper(graphs['gate'], layouts['gate'], lane), 'dormant proof wrapper changed')
            sat(folder, row)
            row = next(r for r in cursor['results'] if r['width'] == width and r['lane'] == lane)
            folder = stage('cursor_relation') / f'w{width}_lane{lane}'
            need((folder / 'cursor.v').read_text() == cursor_text(graphs['gold'], layouts['gold'], lane), 'cursor domain proof changed')
            sat(folder, row)
        for label in ('actual_reset_fault', 'actual_capture_fault'):
            audit_fault(label, width, layouts['gate'])
        fault = read(stage('actual_partition_fault') / 'results.json')
        row = next(r for r in fault['results'] if r['width'] == width)
        need(fault['complete'] and row['detected'] and outcome(row['proof'], (stage('actual_partition_fault') / f'w{width}/cec.log').read_text()) == 'different', 'actual partition fault not detected')
        hashes(ROOT, row['source_hashes'])
        folder = stage('actual_partition_fault') / f'w{width}'
        mutated_graph = read(stage('actual_reset_fault') / f'w{width}/cut.json')['modules']['step_gate']
        mutated_layout = read(stage('actual_reset_fault') / f'w{width}/state.json')
        need((folder / 'gate.v').read_text() == wrapper('gate', mutated_graph['ports'], layouts['gold'], mutated_layout, codebook), 'actual CEC fault wrapper changed')
        index = layouts['gate']['aliases']['Buffered_Inst.Channels_Inst.Packer_Inst.r_prefer_fc'][0]
        need(row['outputs'] == [f'c_next[{index}]'], 'actual fault observation changed')
        for side, raw_path in [('gold', source / 'gold.blif'), ('gate', folder / 'gate_raw.blif')]:
            audit_partition(Network(raw_path.read_text()), (folder / f'{side}.blif').read_text(), row['outputs'])
        evidence['results'].append(dict(width=width, complete_partitions=parts,
                                        public_macro_output_bits=4144, actual_gold_state_bits=layouts['gold']['state_bits'],
                                        actual_gate_state_bits=layouts['gate']['state_bits']))
    evidence.update(complete=True, mapped_equivalence=True)
    dump(output, evidence)
    print(json.dumps(evidence, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

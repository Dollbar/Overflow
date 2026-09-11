"""Run: python3 [-O] verification/tl_prepared_partition/check_selection.py [--adopted].
Audits staged selection RTL against immutable baseline, complete real state CEC,
independent reset/capture, oracle traces, mutations and actual mapped STA inputs.
Writes build/verification/tl_selection_reduction/evidence.json. Next adopt the
byte-identical candidate and continue 640 ps optimization/full-top integration.
"""
from pathlib import Path
import argparse
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'verification/tl_partition_mapping'))
from run_cec import dump, need, sha, prune_dead_names
from mapped_state import observe, audit_cut
from run_mapped import FIELDS, interface, step_text
from run_mapped_cec import declarations, port_names
from check_mapped import binary_outputs
from run_faults import FAULTS
from run_selection_equivalence import REFERENCE
from run_timing import CORNERS
from scripts.check_sta_report import check_report

STAGE = ROOT / 'build/verification/tl_selection_reduction'
PREPARED = ROOT / 'build/verification/tl_prepared_partition'
MAPPED = ROOT / 'build/verification/tl_prepared_mapping'
CANDIDATE = STAGE / 'direct_accounts/tl_prepared_partition.v'


def read(path):
    return json.loads(path.read_text())


def matrix(rows, widths):
    need(sorted(r['width'] for r in rows) == sorted(widths), 'exact width matrix')


def identities(report):
    for name, digest in report['sources'].items():
        need(sha(ROOT / name) == digest, 'unchanged actual source ' + name)


def graphs(folder, width):
    layouts = {}
    for side in ('gold', 'gate'):
        original = read(folder / f'{side}_original.json')['modules']['tl_prepared_partition']
        interface(original, width)
        graph = read(folder / f'{side}_observed.json')['modules']['tl_prepared_partition']
        need(set(graph['ports']) == set(original['ports']) | set(FIELDS), 'exact observed interface')
        cut = read(folder / f'{side}_cut.json')['modules']['step_' + side]
        layout = read(folder / f'{side}_state.json')
        observe(graph, FIELDS)
        audit_cut(graph, cut, layout)
        need(set(layout['aliases']) == set(FIELDS), 'complete semantic state')
        constants = [(n, i, b) for n, bits in layout['aliases'].items() for i, b in enumerate(bits) if isinstance(b, str)]
        need(constants == [('r_counts', i, '0') for i in range(0, 32, 4)], 'only declared constant count bits')
        need(layout['state_bits'] == 855 + 20 * (width + 1), 'all actual register bits')
        layouts[side] = layout
    need(layouts['gold']['aliases'] == layouts['gate']['aliases'], 'exact semantic state pairing')
    return layouts


def cec(base, parent, label, widths):
    report = read(base / label / 'results.json')
    need(report['complete'] and report['parent'] == parent, 'complete intended CEC')
    matrix(report['results'], widths)
    for row in report['results']:
        width = row['width']; source = base / parent / f'w{width}'; folder = base / label / f'w{width}'
        layouts = graphs(source, width)
        for name, digest in row['parent_hashes'].items():
            need(sha(source / name) == digest, 'CEC input graph identity')
        need(row['prepare']['exit'] == row['proof']['exit'] == 0 and row['equivalent'], 'actual CEC completion')
        log = (folder / 'proof.log').read_text()
        need(log.count('Networks are equivalent.') == 1 and not re.search(r'Warning:|Error:|ERROR:', log), 'unconditional CEC success')
        names = read(folder / 'ports.json'); need(names['gold'] == names['gate'], 'complete CEC port pairing')
        for side in ('gold', 'gate'):
            graph = read(source / f'{side}_cut.json')['modules']['step_' + side]
            live, pruned = prune_dead_names((folder / f'{side}.blif').read_text())
            need(live == (folder / f'{side}_live.blif').read_text() and pruned == read(folder / f'{side}_prune.json'), 'only dead alias pruning')
            for direction, directive in (('input', '.inputs'), ('output', '.outputs')):
                expected = {b for n, p in graph['ports'].items() if p['direction'] == direction for b in port_names(n, p)}
                need(set(declarations(live, directive)) == expected and declarations(live, directive) == names[side][direction], 'all actual CEC inputs/outputs')
        count = layouts['gold']['state_bits']
        need(row['actual_next_state_bits'] == count and row['cec_output_bits'] == 531 + count + count + 8, 'complete original/next/observed outputs')


def sat(folder, proof, width, layouts, case):
    need(proof['passed'] and proof['proof']['exit'] == 0, 'completed SAT relation')
    need('SAT proof finished - no model found: SUCCESS!' in (folder / 'proof.log').read_text(), 'actual SAT success')
    need((folder / 'step.v').read_text() == step_text(width, layouts, case), 'complete independent reset/capture equations')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adopted', action='store_true'); args = parser.parse_args()
    digest = sha(CANDIDATE)
    adopted = sha(ROOT / 'rtl/tl/tl_prepared_partition.v') == digest
    need(not args.adopted or adopted, 'production must equal the verified candidate')
    for parent, label, reset, widths in (
        ('direct_pair', 'direct_cec', 'direct_reset', [8, 16]),
        ('direct_other_pair', 'direct_other_cec', 'direct_other_reset', list(range(9, 16))),
    ):
        report = read(STAGE / parent / 'results.json'); identities(report)
        need(report['complete'] and report['reference'] == REFERENCE and report['mode'] == 'rtl_pair' and report['library'] is None, 'immutable RTL-pair origin')
        matrix(report['results'], widths)
        need(sha(STAGE / parent / 'candidate.v') == digest, 'exact staged candidate')
        for name in ('tl_prepared_partition.v', 'tl_control_decode.v', 'tl_control_tenure.v'):
            baseline = subprocess.check_output(['git', 'show', REFERENCE + ':rtl/tl/' + name], cwd=ROOT)
            need((STAGE / parent / name).read_bytes() == baseline, 'immutable actual baseline source')
            if name != 'tl_prepared_partition.v':
                need((ROOT / 'rtl/tl' / name).read_bytes() == baseline, 'unchanged dependency')
        cec(STAGE, parent, label, widths)
        rr = read(STAGE / reset / 'results.json')
        need(rr['complete'] and rr['parent'] == parent and sorted((r['width'], r['case']) for r in rr['results']) == sorted((w, c) for w in widths for c in ('reset', 'empty')), 'exact independent-state SAT matrix')
        for row in rr['results']:
            width = row['width']; source = STAGE / parent / f'w{width}'
            for name, value in row['source_hashes'].items(): need(sha(source / name) == value, 'same actual SAT graph')
            sat(STAGE / reset / f'w{width}' / row['case'], row, width, graphs(source, width), row['case'])
    lemma = read(STAGE / 'direct_masks/results.json')
    need(lemma['complete'] and lemma['candidate_sha256'] == digest == sha(STAGE / 'direct_masks/candidate.v') and lemma['combinations'] == 1 << 20 and lemma['protocol_assumptions'] == [], 'actual assignment exhaustive lemma')
    need(lemma['proof']['exit'] == 0 and 'SAT proof finished - no model found: SUCCESS!' in (STAGE / 'direct_masks/proof.log').read_text(), 'actual mask SAT success')
    for expression in (r'assign selected_sectors\[sector\]=[^;]+;', r'assign tag_eligible\[boundary\]=[^;]+;', r'assign selected_tags\[tag\]=[^;]+;'):
        extracted = re.findall(expression, CANDIDATE.read_text())
        need(len(extracted) == 1 and re.findall(expression, (STAGE / 'direct_masks/proof.v').read_text()) == extracted, 'proved assignments extracted from actual RTL')
    unit = PREPARED / 'selection_direct_unit'; report = read(unit / 'results.json'); identities(report)
    need(report['complete'] and sha(unit / 'sources/tl_prepared_partition.v') == digest, 'same actual oracle candidate')
    matrix(report['results'], range(8, 17))
    for name in ('prepared_partition', 'control_partition', 'credit_admission', 'credit_context', 'tl_tenure'):
        need(sha(unit / f'sources/{name}.py') == sha(ROOT / f'model/tl/{name}.py'), 'unchanged independent oracle')
    for row in report['results']:
        folder = unit / f'w{row["width"]}'
        actual = binary_outputs((folder / 'actual.hex').read_text().splitlines())
        expected = binary_outputs((folder / 'expected.hex').read_text().splitlines())
        need(row['compile_exit'] == row['run_exit'] == 0 and row['passed'] and len(actual) == row['vectors'] == 7718 and actual == expected, 'all 531 outputs against independent oracle')
        need(row['coverage']['replaced'] == 100, 'simultaneous retire/replace exercised')
    faultdir = PREPARED / 'selection_direct_faults'; faults = read(faultdir / 'results.json')
    need(faults['complete'] and faults['source_sha256'] == digest and faults['healthy_sha256'] == sha(unit / 'results.json'), 'exact current negative source and healthy run')
    need(sorted((r['fault'], r['width']) for r in faults['results']) == sorted((f, w) for f in FAULTS for w in (8, 16)), 'complete real mutation matrix')
    for row in faults['results']:
        folder = faultdir / row['fault']; old, new = FAULTS[row['fault']]
        need(CANDIDATE.read_text().count(old) == 1 and (folder / CANDIDATE.name).read_text() == CANDIDATE.read_text().replace(old, new) and sha(folder / CANDIDATE.name) == row['candidate_sha256'], 'one actual intended RTL mutation')
        output = folder / f'w{row["width"]}'
        for name in ('vectors.hex', 'expected.hex'): need(sha(output / name) == sha(unit / f'w{row["width"]}' / name), 'unchanged fault oracle')
        log = (output / 'run.log').read_text()
        need(row['compile']['exit'] == 0 and row['detected'] and row['run']['exit'] not in (0, 124) and 'FATAL:' in log and 'prepared vector ' in log, 'actual functional failure, not setup error')
    timingdir = PREPARED / 'selection_direct_timing'; timing = read(timingdir / 'results.json'); identities(timing)
    need(timing['complete'] and timing['candidate_sha256'] == digest == sha(timingdir / 'candidate.v'), 'exact measured candidate')
    mapped = read(MAPPED / 'selection_direct_mapped/results.json'); identities(mapped)
    need(mapped['complete'] and mapped['timing_report_sha256'] == sha(timingdir / 'results.json') and mapped['cases_requested'] == ['reset', 'empty'] and mapped['fault'] is None, 'same measured positive mapped relation')
    need(sha(Path(mapped['library']['path'])) == mapped['library']['sha256'], 'actual mapped Liberty identity')
    matrix(mapped['results'], [8, 16]); matrix(timing['widths'], [8, 16])
    cec(MAPPED, 'selection_direct_mapped', 'selection_direct_mapped_cec', [8, 16])
    physical = []
    for row in mapped['results']:
        width = row['width']; folder = MAPPED / 'selection_direct_mapped' / f'w{width}'; layouts = graphs(folder, width)
        measured = next(r for r in timing['widths'] if r['width'] == width); timed = timingdir / f'width{width}'
        need(sha(folder / 'mapped.v') == sha(timed / 'mapped.v') == row['netlist_sha256'] == measured['netlist_sha256'], 'actual STA netlist correspondence')
        need(sorted(r['case'] for r in row['cases']) == ['empty', 'reset'], 'mapped reset/capture matrix')
        for proof in row['cases']: sat(folder / proof['case'], proof, width, layouts, proof['case'])
        need(measured['mapping']['exit'] == 0 and sorted((r['corner'], r['period_ns']) for r in measured['sta']) == sorted((c, p) for c in CORNERS for p in (0.64, 6.4)), 'five corners and two unchanged periods')
        for entry in measured['sta']:
            lib = timing['libraries'][entry['corner']]; need(sha(Path(lib['path'])) == lib['sha256'], 'actual corner library')
            log = (timed / f'{entry["corner"]}_{entry["period_ns"]:.3f}.log').read_text()
            values = re.findall(r'^worst slack max\s+(\S+)', log, re.M)
            need(len(values) == 1 and float(values[0]) == entry['setup_slack_ns'], 'actual measured setup slack')
            if entry['period_ns'] == 6.4:
                check_report(log, design='prepared_partition'); need(entry['exit'] == 0 and entry['report_gate'], 'reference STA passes full gate')
            else:
                need(entry['exit'] == 1 and not entry['report_gate'] and entry['setup_slack_ns'] < 0, 'main STA failure retained')
        area = read(timed / 'area.json')['design']
        physical.append(dict(width=width, cells=area['num_cells'], area_um2=area['area'], worst_main_setup_ns=min(r['setup_slack_ns'] for r in measured['sta'] if r['period_ns'] == 0.64), worst_reference_setup_ns=min(r['setup_slack_ns'] for r in measured['sta'] if r['period_ns'] == 6.4)))
    peerbase = ROOT / 'build/verification/tl_control_partition'
    peer = read(peerbase / 'selection_direct_peer_evidence.json')
    need(peer == read(peerbase / 'selection_direct_peer_evidence_optimized.json') and peer['actual_configs'] == 32 and peer['scope'] == 'actual_peer_traces_only', 'normal/optimized full actual peer audits')
    for label in ('selection_direct_peers', 'selection_direct_minimum'):
        report = read(peerbase / label / 'results.json'); identities(report)
        need(report['complete'] and digest in report['sources'].values(), 'actual peer candidate and completion')
    static = read(STAGE / 'direct_accounts_static.json')
    need(static['ok'] and static['errors'] == 0 and static['warnings'] == 19, 'RTL artifact gate')
    need(not re.search(r'%Warning|%Error', (STAGE / 'direct_lint.log').read_text()), 'strict Verilog-2001 lint')
    evidence = dict(complete=True, adopted=adopted, rtl_sha256=digest, reference=REFERENCE, scope='binary post-reset module equivalence; complete outputs and actual next-state; unchanged capture latency and ownership', rtl_widths=list(range(8, 17)), rtl_full_state_cec=9, rtl_reset_capture_queries=18, selection_combinations=1 << 20, unit_vectors=69462, actual_rtl_fault_detections=28, actual_peer_configs=32, peer_partitioning=peer['partitioning'], mapped_full_state_cec=2, mapped_reset_capture_queries=4, mapped_equivalence=True, current_candidate_gate_simulation_rerun=False, physical=physical, main_sta_passed=0, reference_sta_passed=10, artifact_errors=0, artifact_advisories=19, main_frequency_closed=False, full_top_sta=False, full_goal_complete=False)
    dump(STAGE / 'evidence.json', evidence); print(json.dumps(evidence, indent=2))


if __name__ == '__main__':
    main()

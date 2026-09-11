"""Run python3 [-O] verification/tl_prepared_partition/check_evidence.py.
Checks exact current sources, all actual edge observations, real fault mismatches,
dual-peer audit and complete process measurements. Outputs evidence.json in
build/verification/tl_prepared_partition. Next close formal/equivalence/main STA;
this evidence gate deliberately does not certify those unfinished requirements.
"""
from pathlib import Path
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.check_sta_report import check_report
STAGE = ROOT / 'build/verification/tl_prepared_partition'


def need(condition, message):
    if not condition: raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def identities(report):
    for name, digest in report['sources'].items(): need(sha(ROOT / name) == digest, 'source identity: '+name)


def holding_cone(graph):
    """Conservative cell fan-in walk; no logical or free-signal cuts."""
    states = {b for c in graph['cells'].values() if c['type']=='$dff' for b in c['connections']['Q']}
    names = ('r_owned','r_cursor','r_control','r_tags','r_capacity','r_auth','r_shared','r_error','r_starts','r_application','r_counts','r_slots')
    proved = {b for n in names for b in graph['netnames'][n]['bits']}
    need(states <= proved, 'state-holding assertion omits actual state')
    inputs = {b:n for n,p in graph['ports'].items() if p['direction']=='input' for b in p['bits']}
    drivers = {}
    for cell in graph['cells'].values():
        if cell['type']=='$dff': continue
        roots = [b for n,bits in cell['connections'].items() if cell['port_directions'][n]=='input' for b in bits]
        for n,bits in cell['connections'].items():
            if cell['port_directions'][n]=='output':
                for bit in bits:
                    if isinstance(bit,int): need(bit not in drivers, 'multiple drivers'); drivers[bit] = roots
    cache = {}
    def walk(bit):
        if isinstance(bit,str) or bit in states: return set()
        if bit in inputs: return {inputs[bit]}
        if bit not in cache:
            need(bit in drivers, 'undriven output cone')
            cache[bit] = set().union(*(walk(b) for b in drivers[bit]))
        return cache[bit]
    ports = ('o_valid','o_error','o_shortfall','o_control','o_tags','o_fields','o_end','o_cursor')
    roots = {name: sorted(set().union(*(walk(b) for b in graph['ports'][name]['bits']))) for name in ports}
    need(all(set(v) <= {'i_rstn'} for v in roots.values()), 'live source/done/ready affects held payload')
    return dict(state_bits=len(states), held_output_input_roots=roots)


def main():
    unit = read(STAGE / 'unit_semantics/results.json'); identities(unit)
    need(unit['complete'] and unit['sources_unchanged'], 'unit completion')
    need([r['width'] for r in unit['results']] == list(range(8,17)), 'nine-width denominator')
    vector_count = 0
    for row in unit['results']:
        folder = STAGE / 'unit_semantics' / f'w{row["width"]}'
        need(row['compile_exit'] == row['run_exit'] == 0 and row['passed'], 'actual unit pass')
        expected = [int(s,16) for s in (folder / 'expected.hex').read_text().splitlines()]
        actual = [int(s,16) for s in (folder / 'actual.hex').read_text().splitlines()]
        vectors = (folder / 'vectors.hex').read_text().splitlines()
        need(len(vectors) == len(actual) == row['vectors'] and actual == expected, 'all 531 public bits at every edge')
        need(all(row['coverage'].values()) and row['coverage']['replaced'] >= 100, 'directed ownership/throughput coverage')
        c = row['coverage']; need(c['captured'] == c['group_done']+c['cancelled'], 'terminal ownership conservation')
        vector_count += len(actual)
    faults = read(STAGE / 'faults_verified/results.json')
    need(faults['complete'] and len(faults['results']) == 28, 'fourteen actual faults at two widths')
    need(faults['source_sha256'] == sha(ROOT / 'rtl/tl/tl_prepared_partition.v') and faults['healthy_sha256'] == sha(STAGE / 'unit_semantics/results.json'), 'fault/healthy source binding')
    need(len({(r['fault'],r['width']) for r in faults['results']}) == 28, 'unique fault denominator')
    for row in faults['results']:
        folder = STAGE / 'faults_verified' / row['fault']
        need(row['candidate_sha256'] == sha(folder / 'tl_prepared_partition.v') != faults['source_sha256'], 'actual source mutation')
        need(row['detected'] and row['compile']['exit'] == 0 and row['run']['exit'] not in (0,124), 'mismatch not elaboration/timeout')
        log = (folder / f'w{row["width"]}' / 'run.log').read_text()
        match = re.search(r'prepared vector (\d+) actual=(\S+) expected=(\S+)',log)
        need(match and match[2] != match[3] and 'FATAL:' in log, 'actual mismatch witness')
    peers_base = ROOT / 'build/verification/tl_control_partition'
    for mode in ('prepared_peers','prepared_minimum'):
        report = read(peers_base / mode / 'results.json'); identities(report)
        need(report['complete'] and len(report['results']) == 16 and all(r['prepared'] and r['passed'] for r in report['results']), 'actual prepared peer modes')
    peer = read(peers_base / 'prepared_evidence.json')
    need(peer == read(peers_base / 'prepared_evidence_optimized.json') and peer['actual_configs'] == 32, 'independent peer audit in both Python modes')
    timing = read(STAGE / 'timing/results.json'); identities(timing)
    need(timing['complete'] and timing['sources_unchanged'] and timing['candidate_sha256'] == sha(ROOT / 'rtl/tl/tl_prepared_partition.v'), 'actual timing source')
    physical = []
    for row in timing['widths']:
        folder = STAGE / 'timing' / f'width{row["width"]}'
        need(row['mapping']['exit'] == 0 and sha(folder / 'mapped.v') == row['netlist_sha256'], 'actual mapped artifact')
        graph = read(folder / 'mapped.json')['modules']['tl_prepared_partition']
        need(sum(len(p['bits']) for p in graph['ports'].values() if p['direction']=='output') == 531, 'actual mapped public outputs')
        need(len(row['sta']) == 10, 'five corners and two periods')
        for item in row['sta']:
            library = timing['libraries'][item['corner']]; need(sha(Path(library['path'])) == library['sha256'], 'actual library identity')
            log = (folder / f'{item["corner"]}_{item["period_ns"]:.3f}.log').read_text()
            slack = re.findall(r'^worst slack max\s+(\S+)',log,re.M)
            need(len(slack) == 1 and float(slack[0]) == item['setup_slack_ns'], 'actual reported slack')
            if item['period_ns'] == 6.4:
                need(item['exit'] == 0 and item['report_gate'], 'reference STA diagnostics')
                check_report(log, design='prepared_partition')
            else:
                need(item['exit'] != 0 and not item['report_gate'] and item['setup_slack_ns'] < 0, 'main violations must remain failed')
        area = read(folder / 'area.json')['design']
        physical.append(dict(width=row['width'],cells=area['num_cells'],area_um2=area['area'],worst_main_setup_ns=min(s['setup_slack_ns'] for s in row['sta'] if s['period_ns']==.64),worst_reference_setup_ns=min(s['setup_slack_ns'] for s in row['sta'] if s['period_ns']==6.4)))
    need([r['width'] for r in physical] == [8,16], 'mapped width denominator')
    skill = read(STAGE / 'skill_gate.json'); need(skill['ok'] and skill['errors'] == 0, 'authored RTL static artifact gate')
    lint = (STAGE / 'lint.log').read_text(); need('%Warning' not in lint and '%Error' not in lint and 'Verilator:' in lint, 'strict lint diagnostics')
    formal = read(STAGE / 'ownership_formal/results.json'); identities(formal)
    need(formal['complete'] and formal['properties']=='ownership' and not formal['undef_encoding'], 'binary ownership induction')
    need([r['width'] for r in formal['results']] == [8,16], 'ownership proof width denominator')
    cones = []
    for row in formal['results']:
        folder = STAGE / 'ownership_formal' / f'w{row["width"]}'
        need(row['passed'] and row['proof']['exit']==0 and 'Induction step proven: SUCCESS!' in (folder/'proof.log').read_text(), 'actual ownership proof')
        cones.append(dict(width=row['width'], **holding_cone(read(folder/'structure.json')['modules']['tl_prepared_partition'])))
    negative_proofs = 0
    for label in ('formal_fault_overwrite','formal_fault_reset'):
        report = read(STAGE / label / 'results.json'); identities(report)
        need(not report['complete'] and [r['width'] for r in report['results']]==[8,16], 'formal negative denominator')
        for row in report['results']:
            folder = STAGE / label / f'w{row["width"]}'
            log = (folder/'proof.log').read_text()
            need(row['structural']['exit']==0 and row['proof']['exit'] not in (0,124) and 'model found for base case: FAIL!' in log and read(folder/'witness.json')['signal'], 'actual SAT negative witness, not timeout')
            negative_proofs += 1
    compatibility = read(STAGE/'compatibility.json'); need(compatibility['exit']==0, 'clean-export compatibility')
    evidence = dict(functional_stage_complete=True,unit_widths=list(range(8,17)),unit_vectors=vector_count,actual_peer_configs=32,actual_unit_faults=28,ownership_induction_widths=[8,16],compositional_output_holding=cones,formal_fault_witnesses=negative_proofs,physical=physical,reference_sta_passed=10,main_sta_passed=0,artifact_errors=skill['errors'],artifact_advisories=skill['warnings'],compatibility_exit=0,full_functional_formal=False,mapped_equivalence=False,main_frequency_closed=False,full_top_sta=False,full_goal_complete=False)
    for label in ('formal','binary_formal'):
        path = STAGE / label / 'results.json'
        if path.is_file(): evidence[label] = read(path)
    (STAGE / 'evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps(evidence,indent=2))


if __name__ == '__main__':
    main()

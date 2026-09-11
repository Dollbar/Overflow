"""Run: python3 [-O] verification/tl_prepared_partition/check_cost_evidence.py [--adopted].
Audit current carry-save candidate, complete actual state CEC/reset/capture,
independent oracle/fault/peer traces, arithmetic/context relation and actual STA.
Writes build/verification/tl_cost_compression/evidence.json. Next preserve exact
source on adoption, then continue full-top integration and 640 ps closure.
"""
from pathlib import Path
import argparse
import json
import re
import sys
import subprocess

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import need,dump,sha
from check_selection import read,matrix,identities,graphs,cec,sat
from check_mapped import binary_outputs
from run_faults import FAULTS
from run_selection_equivalence import REFERENCE as GRAPH_REFERENCE
from run_timing import CORNERS
from scripts.check_sta_report import check_report
from check_cost_relation import main as audit_relation

STAGE=ROOT/'build/verification/tl_cost_compression'
PAIR=ROOT/'build/verification/tl_selection_reduction'
PREPARED=ROOT/'build/verification/tl_prepared_partition'
MAPPED=ROOT/'build/verification/tl_prepared_mapping'
CANDIDATE=STAGE/'candidate/tl_prepared_partition.v'


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--adopted',action='store_true');a=p.parse_args()
    digest=sha(CANDIDATE);adopted=sha(ROOT/'rtl/tl/tl_prepared_partition.v')==digest
    need(not a.adopted or adopted,'same adopted candidate')
    audit_relation();relation=read(STAGE/'relation.json');need(relation['complete'] and relation['candidate_sha256']==digest,'exact arithmetic/context relation')
    for parent,label,reset,widths in [('cost_pair','cost_cec','cost_reset',[8,16]),('cost_other_pair','cost_other_cec','cost_other_reset',list(range(9,16)))]:
        report=read(PAIR/parent/'results.json');identities(report);need(report['complete'] and report['mode']=='rtl_pair' and report['library'] is None,'actual two-RTL graph preparation');matrix(report['results'],widths)
        need(sha(PAIR/parent/'candidate.v')==digest,'exact actual graph candidate')
        need(report['reference']==GRAPH_REFERENCE,'immutable graph reference')
        for name in ('tl_prepared_partition.v','tl_control_decode.v','tl_control_tenure.v'):
            need((PAIR/parent/name).read_bytes()==subprocess.check_output(['git','show',GRAPH_REFERENCE+':rtl/tl/'+name],cwd=ROOT),'actual immutable reference/dependency source')
        cec(PAIR,parent,label,widths)
        rr=read(PAIR/reset/'results.json');need(rr['complete'] and rr['parent']==parent and sorted((r['width'],r['case']) for r in rr['results'])==sorted((w,c) for w in widths for c in ('reset','empty')),'complete RTL reset/capture matrix')
        for row in rr['results']:
            width=row['width'];source=PAIR/parent/f'w{width}'
            for name,value in row['source_hashes'].items():need(sha(source/name)==value,'same actual SAT input graph')
            sat(PAIR/reset/f'w{width}'/row['case'],row,width,graphs(source,width),row['case'])
    for label,widths in [('cost_compression_unit',[8,16]),('cost_compression_other_unit',list(range(9,16)))]:
        unit=PREPARED/label;report=read(unit/'results.json');identities(report)
        need(report['complete'] and sha(unit/'sources/tl_prepared_partition.v')==digest,'actual independent-oracle candidate');matrix(report['results'],widths)
        for name in ('prepared_partition','control_partition','credit_admission','credit_context','tl_tenure'):
            need(sha(unit/f'sources/{name}.py')==sha(ROOT/f'model/tl/{name}.py'),'unchanged independent oracle')
        for row in report['results']:
            folder=unit/f'w{row["width"]}';actual=binary_outputs((folder/'actual.hex').read_text().splitlines());expected=binary_outputs((folder/'expected.hex').read_text().splitlines())
            need(row['compile_exit']==row['run_exit']==0 and row['passed'] and len(actual)==row['vectors']==7718 and actual==expected,'all 531 public output bits against independent oracle')
            need(row['coverage']['replaced']==100,'actual simultaneous retirement/capture coverage')
    unit=PREPARED/'cost_compression_unit'
    faultdir = PREPARED / 'cost_compression_faults'; faults = read(faultdir / 'results.json')
    need(faults['complete'] and faults['source_sha256'] == digest and faults['healthy_sha256'] == sha(unit / 'results.json'), 'exact current negative source and healthy run')
    need(sorted((r['fault'], r['width']) for r in faults['results']) == sorted((f, w) for f in FAULTS for w in (8, 16)), 'complete real mutation matrix')
    for row in faults['results']:
        folder = faultdir / row['fault']; old, new = FAULTS[row['fault']]
        need(CANDIDATE.read_text().count(old) == 1 and (folder / CANDIDATE.name).read_text() == CANDIDATE.read_text().replace(old, new) and sha(folder / CANDIDATE.name) == row['candidate_sha256'], 'one actual intended RTL mutation')
        output = folder / f'w{row["width"]}'
        for name in ('vectors.hex', 'expected.hex'): need(sha(output / name) == sha(unit / f'w{row["width"]}' / name), 'unchanged fault oracle')
        log = (output / 'run.log').read_text()
        need(row['compile']['exit'] == 0 and row['detected'] and row['run']['exit'] not in (0, 124) and 'FATAL:' in log and 'prepared vector ' in log, 'actual functional failure, not setup error')
    timingdir = PREPARED / 'cost_compression_timing'; timing = read(timingdir / 'results.json'); identities(timing)
    need(timing['complete'] and timing['candidate_sha256'] == digest == sha(timingdir / 'candidate.v'), 'exact measured candidate')
    mapped = read(MAPPED / 'cost_compression_mapped/results.json'); identities(mapped)
    need(mapped['complete'] and mapped['timing_report_sha256'] == sha(timingdir / 'results.json') and mapped['cases_requested'] == ['reset', 'empty'] and mapped['fault'] is None, 'same measured positive mapped relation')
    need(sha(Path(mapped['library']['path'])) == mapped['library']['sha256'], 'actual mapped Liberty identity')
    matrix(mapped['results'], [8, 16]); matrix(timing['widths'], [8, 16])
    cec(MAPPED, 'cost_compression_mapped', 'cost_compression_mapped_cec', [8, 16])
    physical = []
    for row in mapped['results']:
        width = row['width']; folder = MAPPED / 'cost_compression_mapped' / f'w{width}'; layouts = graphs(folder, width)
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
    peer = read(peerbase / 'cost_compression_peer_evidence.json')
    need(peer == read(peerbase / 'cost_compression_peer_evidence_optimized.json') and peer['actual_configs'] == 32 and peer['scope'] == 'actual_peer_traces_only', 'normal/optimized full actual peer audits')
    for label in ('cost_compression_peers', 'cost_compression_minimum'):
        report = read(peerbase / label / 'results.json'); identities(report)
        need(report['complete'] and digest in report['sources'].values(), 'actual peer candidate and completion')
    carrydir=PREPARED/'cost_compression_carry_fault';carry=read(carrydir/'results.json');identities(carry);matrix(carry['results'],[8,16])
    need(not carry['complete'] and sha(carrydir/'sources/tl_prepared_partition.v')==sha(STAGE/'carry_fault/tl_prepared_partition.v'),'same actual carry mutant')
    for row in carry['results']:
        folder=carrydir/f'w{row["width"]}';actual=binary_outputs((folder/'actual.hex').read_text().splitlines());expected=binary_outputs((folder/'expected.hex').read_text().splitlines())
        need(row['compile_exit']==0 and row['run_exit'] not in (0,124) and not row['passed'] and bool(actual),'actual compiled carry failure')
        need([i for i,x in enumerate(actual) if x!=expected[i]]==[len(actual)-1],'first actual carry mismatch after matching prefix')
        for name in ('vectors.hex','expected.hex'):need(sha(folder/name)==sha(unit/f'w{row["width"]}'/name),'same complete independent carry oracle')
    static=read(STAGE/'static.json');need(static['ok'] and static['errors']==0,'authored RTL artifact gate')
    need(not re.search(r'%Warning|%Error',(STAGE/'lint.log').read_text()),'strict Verilog-2001 lint')
    result=dict(complete=True,adopted=adopted,rtl_sha256=digest,scope='binary post-reset module equivalence and actual mapped equivalence; no protocol/ownership/latency change',rtl_widths=list(range(8,17)),rtl_full_state_cec=9,rtl_reset_capture_queries=18,independent_arithmetic_theorems=2,arithmetic_input_bits=48,arithmetic_output_bits=48,arithmetic_assumptions=[],actual_arithmetic_faults=1,unit_vectors=69462,actual_rtl_fault_detections=30,actual_peer_configs=32,peer_partitioning=peer['partitioning'],mapped_full_state_cec=2,mapped_reset_capture_queries=4,mapped_equivalence=True,current_candidate_gate_simulation_rerun=False,physical=physical,main_sta_passed=0,reference_sta_passed=10,artifact_errors=static['errors'],artifact_advisories=static['warnings'],main_frequency_closed=False,full_top_sta=False,full_goal_complete=False)
    dump(STAGE/'evidence.json',result);print(json.dumps(result,indent=2))


if __name__=='__main__':main()

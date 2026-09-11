"""Run: python3 [-O] verification/tl_prepared_partition/check_mapped.py.
Audits the exact mapped sources, complete actual FF D/Q relation, all CEC ports,
reset/empty and constant lemmas, actual mapped negatives and oracle simulations.
Writes build/verification/tl_prepared_mapping/evidence.json. Next timing and
integrated-top work; this closes only this module's binary mapped equivalence.
"""
from pathlib import Path
import json
import re
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,need,sha,prune_dead_names
from mapped_state import observe,audit_cut
from run_mapped import FIELDS,interface,step_text,mutate_netlist
from run_mapped_cec import declarations,port_names

STAGE=ROOT/'build/verification/tl_prepared_mapping'
TIMING=ROOT/'build/verification/tl_prepared_partition/timing'


def read(path):return json.loads(path.read_text())


def binary_outputs(lines):
    values=[]
    for line in lines:
        need(re.fullmatch('[0-9a-fA-F]+',line),'nonbinary hexadecimal output')
        value=int(line,16);need(value<1<<531,'output exceeds complete public interface')
        values.append(value)
    return values


def sat_counterexample(result,log,witness,graph=None):
    aliases={'o_bad'}
    if graph is not None:
        target=graph['ports']['o_bad']['bits']
        need(len(target)==1,'single actual failing output')
        aliases={name for name,port in graph['ports'].items() if port['bits']==target}
    return result['exit'] not in (0,124) and 'ERROR: Called with -verify and proof did fail!' in log and any(
        signal.get('name') in aliases and signal.get('wave','').startswith('1') for signal in witness.get('signal',[]))


def identities(report):
    for name,digest in report['sources'].items():need(sha(ROOT/name)==digest,'actual RTL source identity '+name)
    need(sha(Path(report['library']['path']))==report['library']['sha256'],'actual Liberty unchanged')


def graph_pair(folder,width):
    layouts={}
    for side in ('gold','gate'):
        original=read(folder/f'{side}_original.json')['modules']['tl_prepared_partition'];interface(original,width)
        graph=read(folder/f'{side}_observed.json')['modules']['tl_prepared_partition']
        need(set(graph['ports'])==set(original['ports'])|set(FIELDS),'exact original and state port set')
        cut=read(folder/f'{side}_cut.json')['modules']['step_'+side];layout=read(folder/f'{side}_state.json')
        observe(graph,FIELDS);audit_cut(graph,cut,layout)
        need(set(layout['aliases'])==set(FIELDS),'all semantic state fields')
        constants=[(n,i,b) for n,bits in layout['aliases'].items() for i,b in enumerate(bits) if isinstance(b,str)]
        need(constants==[('r_counts',i,'0') for i in range(0,32,4)],'only eight declared count bits are constant')
        need(layout['state_bits']==(1035 if width==8 else 1195),'full real state denominator')
        layouts[side]=layout
    need(layouts['gold']['aliases']==layouts['gate']['aliases'],'exact common state semantics')
    return layouts


def main():
    timing=read(TIMING/'results.json');healthy=read(STAGE/'actual_relation/results.json');identities(healthy)
    need(healthy['timing_report_sha256']==sha(TIMING/'results.json'),'STA source record')
    cec=read(STAGE/'complete_cec_verified/results.json');need(cec['complete'],'complete CEC matrix')
    need(sorted(r['width'] for r in healthy['results'])==sorted(r['width'] for r in cec['results'])==[8,16],'two-width positive matrix')
    inventory=[]
    for row in healthy['results']:
        width=row['width'];folder=STAGE/'actual_relation'/f'w{width}'
        mapped=TIMING/f'width{width}/mapped.v';timed=next(r for r in timing['widths'] if r['width']==width)
        need(row['prepare']['exit']==0 and sha(mapped)==sha(folder/'mapped.v')==row['netlist_sha256']==timed['netlist_sha256'],'exact STA netlist')
        layouts=graph_pair(folder,width)
        for case in ('reset','empty'):
            proof=next(r for r in row['cases'] if r['case']==case)
            need(proof['passed'] and proof['proof']['exit']==0 and 'SAT proof finished - no model found: SUCCESS!' in (folder/case/'proof.log').read_text(),'actual reset/empty SAT')
            need((folder/case/'step.v').read_text()==step_text(width,layouts,case),'complete reset/empty equation relation')
        cr=next(r for r in cec['results'] if r['width']==width);proof_folder=STAGE/'complete_cec_verified'/f'w{width}'
        for name,digest in cr['parent_hashes'].items():need(sha(folder/name)==digest,'exact CEC graph input '+name)
        need(cr['equivalent'] and cr['proof']['exit']==0,'actual complete CEC result')
        log=(proof_folder/'proof.log').read_text();need(log.count('Networks are equivalent.')==1 and not re.search(r'Warning:|Error:|ERROR:',log),'actual unconditional CEC success')
        names=read(proof_folder/'ports.json');need(names['gold']==names['gate'],'exact CEC port pairing')
        for side in ('gold','gate'):
            graph=read(folder/f'{side}_cut.json')['modules']['step_'+side]
            raw=(proof_folder/f'{side}.blif').read_text();live,pruned=prune_dead_names(raw)
            need(live==(proof_folder/f'{side}_live.blif').read_text() and pruned==read(proof_folder/f'{side}_prune.json'),'only dead alias pruning')
            for direction,directive in (('input','.inputs'),('output','.outputs')):
                expected={b for n,p in graph['ports'].items() if p['direction']==direction for b in port_names(n,p)}
                need(set(declarations(live,directive))==expected and declarations(live,directive)==names[side][direction],'full actual CEC port denominator')
        count=layouts['gold']['state_bits'];need(cr['actual_next_state_bits']==count and cr['cec_output_bits']==531+count+(1043 if width==8 else 1203),'public/next/observation output count')
        inventory.append(dict(width=width,actual_state_bits=count,public_output_bits=531,next_state_bits=count,extra_semantic_observation_bits=1043 if width==8 else 1203))
    constants=ROOT/'build/verification/tl_prepared_partition/mapped_constants';report=read(constants/'results.json')
    need(report['complete'] and report['properties']=='count_constants' and sorted(r['width'] for r in report['results'])==[8,16],'constant state induction matrix')
    for name,digest in report['sources'].items():need(sha(ROOT/name)==digest,'constant lemma RTL identity')
    for row in report['results']:need(row['passed'] and row['proof']['exit']==0 and 'Induction step proven: SUCCESS!' in (constants/f'w{row["width"]}'/'proof.log').read_text(),'actual constant-state induction')
    negatives=[]
    for label,fault,case in (('fault_clock','clock',None),('fault_capture','capture','empty'),('fault_reset','reset','reset'),('fault_output_verified','output','owned')):
        report=read(STAGE/label/'results.json');identities(report);need(report['fault']==fault and sorted(r['width'] for r in report['results'])==[8,16],'real fault matrix')
        for row in report['results']:
            width=row['width'];folder=STAGE/label/f'w{width}';original=(TIMING/f'width{width}/mapped.v').read_text()
            need((folder/'mapped.v').read_text()==mutate_netlist(original,fault) and sha(folder/'mapped.v')==row['netlist_sha256'],'one intended actual mapped mutation')
            if case is None:
                need(row['inventory_error']=='actual positive clock/DFF width','actual clock rejection')
                graph=read(folder/'gate_observed.json')['modules']['tl_prepared_partition']
                need(any(c['type']=='$_DFF_P_' and c['connections']['C']!=graph['ports']['i_clk']['bits'] for c in graph['cells'].values()),'actual wrong-clock FF exists')
            else:
                layouts=graph_pair(folder,width);entry=next(r for r in row['cases'] if r['case']==case)
                need((folder/case/'step.v').read_text()==step_text(width,layouts,case),'same complete negative equation relation')
                need(sat_counterexample(entry['proof'],(folder/case/'proof.log').read_text(),read(folder/case/'witness.json'),read(folder/case/'step.json')['modules']['step']),'actual mapped SAT witness')
            negatives.append(dict(fault=fault,width=width,check=case or 'actual_clock'))
    cec_faults=0
    for label,parent in (('cec_fault_capture','fault_capture'),('cec_fault_output','fault_output_verified'),('cec_fault_reset','fault_reset')):
        report=read(STAGE/label/'results.json');need(not report['complete'] and report['parent']==parent and sorted(r['width'] for r in report['results'])==[8,16],'CEC fault matrix')
        for row in report['results']:
            folder=STAGE/label/f'w{row["width"]}'
            for name,digest in row['parent_hashes'].items():need(sha(STAGE/parent/f'w{row["width"]}'/name)==digest,'same actual fault graph in CEC')
            names=read(folder/'ports.json');need(names['gold']==names['gate'],'complete fault CEC interface pairing')
            need(row['actual_mismatch'] and not row['equivalent'] and row['proof']['exit']==0 and 'Networks are NOT EQUIVALENT.' in (folder/'proof.log').read_text(),'same CEC engine detects actual mapped fault')
            cec_faults+=1
    unit=ROOT/'build/verification/tl_prepared_partition/unit_semantics'
    oracle_manifest=read(ROOT/'build/verification/tl_prepared_partition/manifest.json')
    need(oracle_manifest['commit']=='c34f40f2dc00c2e12283897ea0f3de085abfbc7f','immutable original oracle stage')
    for name,digest in oracle_manifest['tracked_sources'].items():
        if name.startswith('model/'):
            need(sha(ROOT/name)==digest,'independent model source unchanged '+name)
    replay=[]
    for label,negative,widths in (('mapped_vectors_w8',False,[8]),('mapped_vectors_w16',False,[16]),('mapped_fault_vectors',True,[8])):
        report=read(STAGE/label/'results.json');need(report['complete'] and report['expect_mismatch']==negative,'actual mapped simulation completion')
        need(report['oracle_report_sha256']==sha(unit/'results.json'),'independent oracle report identity')
        need(sha(STAGE/label/'cells.v')==report['models_sha256'] and report['library']==healthy['library'],'actual Liberty model identity')
        need(sorted(r['width'] for r in report['results'])==widths,'simulation width denominator')
        for row in report['results']:
            folder=STAGE/label/f'w{row["width"]}';need(row['compile']['exit']==0 and row['passed'],'actual mapped compilation/run')
            for name in ('vectors.hex','expected.hex'):
                fixture=unit/f'w{row["width"]}'/name
                need(sha(fixture)==sha(folder/name)==oracle_manifest['evidence'][str(fixture.relative_to(ROOT))],'immutable independent input/expectation identity')
            need(sha(folder/'mapped.v')==row['netlist_sha256']==sha(STAGE/report['parent']/f'w{row["width"]}'/'mapped.v'),'actual replay mapped artifact')
            actual=binary_outputs((folder/'actual.hex').read_text().splitlines());expected=binary_outputs((folder/'expected.hex').read_text().splitlines())
            need(len(expected)==7718 and bool(actual),'independent oracle vector denominator')
            mismatches=[i for i,x in enumerate(actual) if x!=expected[i]]
            if negative:need(mismatches==[len(actual)-1] and row['run']['exit'] not in (0,124),'actual reset-to-first-failure trace')
            else:need(actual==expected and row['run']['exit']==0,'all 531 actual mapped output bits match independent oracle')
            replay.append(dict(label=label,width=row['width'],vectors=len(actual),negative=negative))
    evidence=dict(complete=True,scope='binary post-reset sequential RTL versus actual TSMC28 mapped module equivalence; independent payload initial states handled by reset/empty relation',rtl_sha256=sha(ROOT/'rtl/tl/tl_prepared_partition.v'),library_sha256=healthy['library']['sha256'],inventory=inventory,full_state_cec=2,reset_queries=2,empty_queries=2,constant_inductions=2,actual_mapped_fault_checks=len(negatives),actual_cec_fault_detections=cec_faults,faults=negatives,mapped_oracle_replay=replay,mapped_equivalence=True,main_frequency_closed=False,full_top_sta=False,full_goal_complete=False)
    dump(STAGE/'evidence.json',evidence);print(json.dumps(evidence,indent=2))


if __name__=='__main__':main()

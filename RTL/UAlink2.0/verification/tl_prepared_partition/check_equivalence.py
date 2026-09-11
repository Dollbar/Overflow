"""Run python3 [-O] verification/tl_prepared_partition/check_equivalence.py.
Audits the reset/step/invariant proof composition, all real FF D/Q mappings,
exhaustive cofactors, immutable baseline and actual paired RTL vectors. Outputs
build/verification/tl_prepared_equivalence/evidence.json. Next actual mapped
equivalence and main timing; this is binary RTL reference preservation only.
"""
from pathlib import Path
import copy
import hashlib
import json
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,need,sha
from run_reference import REFERENCE,DEPENDENCIES
from run_equivalence import OUTPUTS
from run_cases import CASES

STAGE=ROOT/'build/verification/tl_prepared_equivalence'
PRIOR=ROOT/'build/verification/tl_prepared_partition'

# The reference declaration comment was clarified after the proof runs. Accept
# only this exact comment insertion when auditing the immutable old snapshots;
# every other byte, including all RTL tokens, must still match its original hash.
OLD_COMMENT='// 验证参考：独立持有原始字段并使用固定基线分组器'.encode()
NEW_COMMENT='// 验证参考模块：独立持有原始字段并使用固定基线分组器'.encode()


def reference_identity(data,digest):
    if hashlib.sha256(data).hexdigest()==digest:return True
    if data.count(NEW_COMMENT)!=1:return False
    return hashlib.sha256(data.replace(NEW_COMMENT,OLD_COMMENT,1)).hexdigest()==digest


def reference_snapshot(path):
    need(reference_identity(Path(__file__).with_name('reference.v').read_bytes(),sha(path)),
         'reference differs beyond the recorded declaration comment')


def read(path):return json.loads(path.read_text())


def identities(report):
    for name,digest in report['sources'].items():
        path=ROOT/name
        valid=reference_identity(path.read_bytes(),digest) if path.resolve()==Path(__file__).with_name('reference.v').resolve() else sha(path)==digest
        need(valid,'current source identity '+name)


def audit_cut(original,cut,layout):
    """Independently check the FF transition definition against the recorded cut."""
    drivers={};combinational={};clock=original['ports']['i_clk']['bits']
    for name,cell in original['cells'].items():
        if cell['type']=='$dff':
            need(cell['connections']['CLK']==clock and int(cell['parameters']['CLK_POLARITY'],2)==1,'actual edge/clock')
            for q,d in zip(cell['connections']['Q'],cell['connections']['D']):
                need(q not in drivers,'multiple Q drivers');drivers[q]=d
        else:
            need('latch' not in cell['type'].lower(),'latch in step model');combinational[name]=cell
    need(cut['cells']==combinational,'a combinational equation was changed during state observation')
    need(cut['netnames']==original['netnames'],'state observation changed a net alias')
    need({n:p for n,p in cut['ports'].items() if n in original['ports']}==original['ports'],'an original port was changed')
    seen=set();expected_ports=set(original['ports'])
    for field,item in layout['fields'].items():
        q=original['netnames'][item['net']]['bits']
        need(len(q)==len(set(q)) and all(b in drivers and b not in seen for b in q),'Q observation not unique')
        d=[drivers[b] for b in q];seen.update(q)
        need(item['q']==q and item['d']==d and item['width']==len(q),'recorded D/Q differs from actual FF')
        need(cut['ports']['s_'+field]==dict(direction='input',bits=q),'state input is not actual Q')
        need(cut['ports']['n_'+field]==dict(direction='output',bits=d),'next state is not actual D')
        expected_ports.update(('s_'+field,'n_'+field))
    need(seen==set(drivers) and len(seen)==layout['state_bits'] and layout['unclassified_state_bits']==0,'an actual state bit was omitted')
    need(set(cut['ports'])==expected_ports,'unaccounted cut port')
    return len(seen)


def audit_cofactor(original,actual,fixed):
    """Only constant substitution of declared primary inputs may differ."""
    old=original['modules']['step'];new=actual['modules']['step'];sub={}
    for name,value in fixed.items():
        p=old['ports'][name];need(p['direction']=='input' and 0<=value<1<<len(p['bits']),'cofactor domain')
        for index,bit in enumerate(p['bits']):need(isinstance(bit,int) and bit not in sub,'cofactor alias');sub[bit]=str((value>>index)&1)
    def subst(bits):return [sub.get(b,b) for b in bits]
    need(set(new['ports'])==set(old['ports'])-set(fixed),'cofactor port coverage')
    for name,p in new['ports'].items():
        expected=dict(old['ports'][name],bits=subst(old['ports'][name]['bits']));need(p==expected,'cofactor port mutation')
    need(set(new['netnames'])==set(old['netnames']) and set(new['cells'])==set(old['cells']),'cofactor removed a node')
    for name,net in old['netnames'].items():need(new['netnames'][name]==dict(net,bits=subst(net['bits'])),'cofactor net mutation')
    for name,cell in old['cells'].items():
        expected=dict(cell,connections={n:subst(bits) for n,bits in cell['connections'].items()});need(new['cells'][name]==expected,'cofactor cell mutation')


def inductive_reports(root,labels):
    widths=[]
    for label in labels:
        report=read(root/label/'results.json');identities(report);need(report['complete'],'incomplete invariant '+label)
        for row in report['results']:
            need(row['passed'] and row['proof']['exit']==0,'invariant result '+label)
            need('Induction step proven: SUCCESS!' in (root/label/f'w{row["width"]}'/'proof.log').read_text(),'actual inductive log')
            widths.append(row['width'])
    need(sorted(widths)==list(range(8,17)),'nine-width invariant denominator')
    return sorted(widths)


def main():
    metadata_widths=inductive_reports(STAGE,('metadata','metadata_other_widths'))
    boundary_widths=inductive_reports(PRIOR,('boundary_induction','boundary_other_widths'))
    for label in ('metadata','metadata_other_widths'):
        need((STAGE/label/'baseline_admission.v').read_bytes()==subprocess.check_output(['git','show',REFERENCE+':rtl/tl/tl_credit_admission.v'],cwd=ROOT),'immutable metadata baseline')
    reference=read(STAGE/'reference/results.json');need(reference['complete'] and reference['reference']==REFERENCE,'reference replay')
    need(reference_identity(Path(__file__).with_name('reference.v').read_bytes(),reference['reference_sha256']),'raw reference wrapper identity')
    need(sha(STAGE/'reference/reference.v')==reference['reference_sha256'],'raw reference snapshot identity')
    for name in DEPENDENCIES:need((STAGE/'reference'/name).read_bytes()==subprocess.check_output(['git','show',REFERENCE+':rtl/tl/'+name],cwd=ROOT),'reference Git snapshot '+name)
    reference_vectors=0
    for row in reference['results']:
        folder=STAGE/'reference'/f'w{row["width"]}'
        need(row['passed'] and row['compile']['exit']==row['run']['exit']==0,'actual reference simulation')
        actual=[int(x,16) for x in (folder/'actual.hex').read_text().splitlines()];expected=[int(x,16) for x in (folder/'expected.hex').read_text().splitlines()]
        need(actual==expected and len(actual)>7000,'full oracle/reference observations');reference_vectors+=len(actual)
    need({r['width'] for r in reference['results']}=={8,16},'reference width denominator')
    states=[];parents={}
    for label in ('step_observed','step_other_widths'):
        folder=STAGE/label;report=read(folder/'results.json');identities(report);parents[label]=report
        need(report['public_output_bits']==531 and report['composition_required'],'step theorem scope')
        reference_snapshot(folder/'reference.v')
        need((folder/'probe.v').read_bytes()==(STAGE/'metadata/probe.v').read_bytes(),'same proved metadata function')
        for name in DEPENDENCIES:need((folder/name).read_bytes()==(STAGE/'reference'/name).read_bytes(),'step immutable dependency')
        for row in report['results']:
            width=row['width'];b=folder/f'w{width}'
            for side,top in (('gold','tl_prepared_reference'),('gate','tl_prepared_partition')):
                original=read(b/f'{side}_original.json')['modules'][top];cut=read(b/f'{side}_cut.json')['modules']['step_'+side];layout=read(b/f'{side}_state.json')
                need({n:len(p['bits']) for n,p in original['ports'].items() if p['direction']=='output'}==OUTPUTS,'all original output ports')
                inputs=dict(i_clk=1,i_rstn=1,i_source_valid=1,i_ready=1,i_done=1,i_response=1,i_auth=1,i_shared=1,i_source_control=256,i_source_tags=512,i_capacity=20*(width+1))
                need({n:len(p['bits']) for n,p in original['ports'].items() if p['direction']=='input'}==inputs,'all original input ports')
                states.append(dict(width=width,side=side,state_bits=audit_cut(original,cut,layout)))
    need(sorted((x['width'],x['side']) for x in states)==sorted((w,s) for w in range(8,17) for s in ('gold','gate')),'state inventory matrix')
    cases=[]
    for label in ('cases','cases_low','cases_middle','cases_high'):
        folder=STAGE/label;report=read(folder/'results.json');need(report['complete'],'case completion '+label)
        parent=STAGE/report['step_label'];need(report['step_label'] in parents and sha(parent/'results.json')==report['step_report_sha256'],'case parent identity')
        for row in report['results']:
            b=folder/f'w{row["width"]}'/row['case'];source=parent/f'w{row["width"]}'/'step_structure.json'
            need(row['passed'] and row['proof']['exit']==0 and 'SAT proof finished - no model found: SUCCESS!' in (b/'proof.log').read_text(),'actual complete step SAT')
            need(row['fixed']==dict(CASES)[row['case']] and row['source_sha256']==sha(source) and row['cofactor_sha256']==sha(b/'cofactor.json'),'cofactor source/domain identity')
            audit_cofactor(read(source),read(b/'cofactor.json'),row['fixed']);cases.append((row['width'],row['case']))
    need(sorted(cases)==sorted((w,name) for w in range(8,17) for name,_ in CASES),'all ten exhaustive cases per width')
    faults=[]
    for root,label,marker in ((PRIOR,'boundary_fault','model found for base case: FAIL!'),(STAGE,'metadata_fault_counts','model found for base case: FAIL!'),(STAGE,'step_fault_replace','SAT proof finished - model found: FAIL!'),(STAGE,'step_fault_tags','SAT proof finished - model found: FAIL!')):
        report=read(root/label/'results.json');identities(report);need(not report['complete'],'negative proof cannot be complete')
        for row in report['results']:
            folder=root/label/f'w{row["width"]}'
            need(row['proof']['exit'] not in (0,124) and marker in (folder/'proof.log').read_text() and read(folder/'witness.json')['signal'],'actual SAT counterexample, not timeout')
            faults.append((label,row['width']))
    need(len(faults)==8,'formal negative denominator')
    miter=[]
    for label,negative in (('miter_vectors',False),('miter_fault_vectors',True)):
        report=read(STAGE/label/'results.json');need(report['complete'] and report['expect_mismatch']==negative,'actual full miter run')
        for row in report['results']:
            identities(row);folder=STAGE/label/f'w{row["width"]}'
            need(row['compile']['exit']==0 and row['passed'],'actual miter compilation/run')
            expected=[int(x,16) for x in (folder/'expected.hex').read_text().splitlines()];mismatches=[]
            lines=(folder/'paired_trace.txt').read_text().splitlines()
            for index,line in enumerate(lines):
                j,gold,gate,bad=line.split();need(int(j)==index and int(gold,16)==expected[index],'raw reference agrees with oracle up to counterexample')
                need(int(bad)==int(gold!=gate),'actual full miter mismatch wire');mismatches.append(gold!=gate)
            need((any(mismatches) and row['run']['exit'] not in (0,124)) if negative else (not any(mismatches) and len(lines)==len(expected) and row['run']['exit']==0),'reset-to-failure or complete healthy trace')
            miter.append(dict(label=label,width=row['width'],edges=len(lines),negative=negative))
    evidence=dict(complete=True,scope='composed binary post-reset RTL equivalence against immutable raw-field baseline; not independent protocol certification',reference=REFERENCE,rtl_sha256=sha(ROOT/'rtl/tl/tl_prepared_partition.v'),equivalence_widths=list(range(8,17)),public_output_bits=531,metadata_inductions=len(metadata_widths),boundary_inductions=len(boundary_widths),exhaustive_step_queries=len(cases),state_inventory=states,formal_fault_witnesses=len(faults),reference_vectors=reference_vectors,actual_full_miter=miter,mapped_equivalence=False,main_frequency_closed=False,full_top_sta=False,full_goal_complete=False)
    evidence['reference_comment_update']=dict(proved_sha256=reference['reference_sha256'],current_sha256=sha(Path(__file__).with_name('reference.v')),change='exact declaration comment insertion only; all RTL bytes unchanged')
    dump(STAGE/'evidence.json',evidence);print(json.dumps(evidence,indent=2))


if __name__=='__main__':
    main()

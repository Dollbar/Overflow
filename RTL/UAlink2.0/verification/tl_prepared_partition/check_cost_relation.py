"""Run: python3 [-O] verification/tl_prepared_partition/check_cost_relation.py.
Audits both actual arithmetic blocks against the independent 48-bit sum oracle,
then checks exact whole-source substitution against immutable 3127705. Outputs
build/verification/tl_cost_compression/relation.json. Next qualify actual mapped
state, unit/peer behavior and PPA before adoption; direct CEC is a separate run.
"""
from pathlib import Path
import json
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import need,dump,sha
from check_mapped import sat_counterexample

STAGE=ROOT/'build/verification/tl_cost_compression'
REFERENCE='3127705b9aca1051d0915b9b8be51e41216968eb'


def read(path):return json.loads(path.read_text())


def blocks(source,legacy):
    if legacy:
        need(source.count(' assign pair[0]=')==1 and source.count('end endgenerate // 结束复用费用')==1,'unique old cost block')
        start=source.index(' assign pair[0]=');end=source.index('end endgenerate // 结束复用费用',start)
        return 'wire [5:0] pair[0:3];wire [5:0] quad[0:1];\n'+source[start:end]
    matches=re.findall(r'// BEGIN_COST_COMPRESSION\n(.*?)// END_COST_COMPRESSION',source,re.S)
    need(len(matches)==1,'unique new cost block');return matches[0]


def replacement(old,new):
    """Exact context check: pure local combinational block is the only change."""
    start=old.index(' assign pair[0]=');end=old.index('end endgenerate // 结束复用费用',start)
    begin=new.index('// BEGIN_COST_COMPRESSION');finish=new.index('// END_COST_COMPRESSION')+len('// END_COST_COMPRESSION\n')
    substituted=old[:start]+new[begin:finish]+old[end:]
    declaration='wire [5:0] contribution[0:7];wire [5:0] pair[0:3];wire [5:0] quad[0:1];'
    need(substituted.count(declaration)==1,'exact removed local temporary declaration')
    substituted=substituted.replace(declaration,'wire [5:0] contribution[0:7];')
    need(substituted==new,'change outside the proved arithmetic block')
    # Local temporary names must not be referenced or driven elsewhere.
    outer=new[:begin]+new[finish:]
    need(not re.search(r'\bcost_(sum|carry)_\d+\b',outer),'compressor temporary escapes its block')
    need(not re.search(r'\b(pair|quad)\b',old[:start].replace(declaration,'')+old[end:]),'removed original temporary escapes its block')
    body=re.sub(r'//[^\n]*','',blocks(new,False))
    # The oracle module accepts only these local equations and prefix outputs;
    # rejecting other syntax prevents hidden state or a driver of outer context.
    for statement in body.split(';'):
        s=statement.strip()
        if not s:continue
        need(re.fullmatch(r'wire \[5:0\] cost_sum_\d+,cost_carry_\d+',s) or re.fullmatch(r'assign (cost_(sum|carry)_\d+|prefix_cost\[\(account\*8\+[0-7]\)\*6\+:6\])=[\w\s\[\]()+^&|<>*:-]+',s),'pure local combinational replacement syntax')
        if s.startswith('assign '):
            names=re.findall(r'[a-zA-Z_][a-zA-Z_0-9]*',s.split('=',1)[1])
            need(all(n=='contribution' or re.fullmatch(r'cost_(sum|carry)_\d+',n) for n in names),'arithmetic depends only on local contribution values')


def proof_source(body):
    code=['module cost(input [47:0] values,output o_bad);localparam account=0;wire [5:0] contribution[0:7];wire [47:0] prefix_cost,expected;']
    for i in range(8):
        code += [f'assign contribution[{i}]=values[{6*i}+:6];',f'assign expected[{6*i}+:6]='+'+'.join(f'values[{6*j}+:6]' for j in range(i+1))+';']
    code += [body,'assign o_bad=(prefix_cost!=expected);endmodule']
    return '\n'.join(code)+'\n'


def main():
    baseline=subprocess.check_output(['git','show',REFERENCE+':rtl/tl/tl_prepared_partition.v'],cwd=ROOT).decode()
    need((STAGE/'baseline.v').read_text()==baseline,'immutable actual production baseline')
    candidate=(STAGE/'candidate/tl_prepared_partition.v').read_text();replacement(baseline,candidate)
    inventory=[]
    for label,source,legacy in [('baseline_lemma',baseline,True),('lemma',candidate,False)]:
        folder=STAGE/label;report=read(folder/'results.json')
        need(report['complete'] and report['proof']['exit']==0 and report['input_bits']==report['output_bits']==48 and report['assumptions']==[],'unconditional arithmetic theorem')
        need((folder/'candidate.v').read_text()==source and sha(folder/'candidate.v')==report['candidate_sha256'],'proved actual source identity')
        need((folder/'proof.v').read_text()==proof_source(blocks(source,legacy)),'exact actual block and independent sum miter')
        script=(folder/'proof.ys').read_text()
        need(script==f'read_verilog "{folder}/proof.v"\nprep -top cost\ncheck -assert\nsat -prove o_bad 0 -verify -dump_json "{folder}/witness.json"\n','no proof assumptions or output omissions')
        need('SAT proof finished - no model found: SUCCESS!' in (folder/'proof.log').read_text(),'actual arithmetic SAT success')
        inventory.append(dict(label=label,input_bits=48,output_bits=48,assumptions=[]))
    folder=STAGE/'carry_fault_proof';negative=read(folder/'results.json');fault=(STAGE/'carry_fault/tl_prepared_partition.v').read_text()
    need(fault==candidate.replace('))<<1;','))<<2;',1),'one actual carry shift mutation')
    need((folder/'candidate.v').read_text()==fault and sha(folder/'candidate.v')==negative['candidate_sha256'],'negative source identity')
    need((folder/'proof.v').read_text()==proof_source(blocks(fault,False)),'same complete arithmetic miter for fault')
    need(sat_counterexample(negative['proof'],(folder/'proof.log').read_text(),read(folder/'witness.json')),'actual carry arithmetic counterexample')
    # Verify context checking rejects a real, unrelated output mutation.
    tampered=candidate.replace('o_taken=o_valid&&i_ready','o_taken=o_valid')
    need(tampered!=candidate,'negative context mutation exists')
    try:replacement(baseline,tampered)
    except ValueError as error:need(str(error)=='change outside the proved arithmetic block','specific context rejection')
    else:raise ValueError('unproved outside change accepted')
    dependencies={}
    for name in ('tl_control_decode.v','tl_control_tenure.v'):
        need((ROOT/'rtl/tl'/name).read_bytes()==subprocess.check_output(['git','show',REFERENCE+':rtl/tl/'+name],cwd=ROOT),'unchanged actual decoder/tenure context')
        dependencies[name]=sha(ROOT/'rtl/tl'/name)
    result=dict(complete=True,reference=REFERENCE,reference_sha256=sha(STAGE/'baseline.v'),candidate_sha256=sha(STAGE/'candidate/tl_prepared_partition.v'),dependencies=dependencies,scope='compositional whole-module binary output and state-transition equivalence by unconditional arithmetic identities and exact context substitution',widths=list(range(8,17)),unchanged_state_and_clock=True,unchanged_capture_latency_and_retire_replace=True,arithmetic_lemmas=inventory,actual_arithmetic_fault_detections=1,context_mutation_rejections=1,direct_whole_module_cec_claim=False,mapped_equivalence_claim=False,full_goal_complete=False)
    dump(STAGE/'relation.json',result);print(json.dumps(result,indent=2))


if __name__=='__main__':main()

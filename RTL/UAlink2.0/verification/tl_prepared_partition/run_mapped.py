"""Run: python3 verification/tl_prepared_partition/run_mapped.py --label mapped
[--widths 8 16] [--timing-root DIR] [--seconds 180]. Uses the exact mapped
netlists and authorized Liberty recorded in the completed timing run. Outputs
source snapshots, original/full state graphs, D/Q cuts, reset/empty/owned SAT
logs and witnesses under build/verification/tl_prepared_mapping/LABEL. Next
audit actual faults and combine the three obligations with constant-state lemma.
"""
from pathlib import Path
import argparse
import json
import re
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha
from run_equivalence import OUTPUTS
from mapped_state import observe

FIELDS=['r_owned','r_cursor','r_error','r_auth','r_shared','r_control','r_tags','r_capacity','r_starts','r_application','r_counts','r_slots']


def mutate_netlist(source,fault):
    if not fault:return source
    if fault=='output':
        anchor='.ZN(o_tags[0])'
        need(source.count(anchor)==1 and source.count('endmodule')==1,'actual tag output driver anchor')
        return source.replace(anchor,'.ZN(fault_saved_output)').replace('endmodule',"wire fault_saved_output;assign o_tags[0]=fault_saved_output^(i_rstn&o_valid);\nendmodule")
    target='r_control[0]' if fault=='capture' else 'r_owned'
    pattern=r'DFQD2BWP40P140\s+\S+\s*\(\s*\.CP\(i_clk\),\s*\.D\([^()]+\),\s*\.Q\('+re.escape(target)+r'\)\s*\);'
    matches=list(re.finditer(pattern,source));need(len(matches)==1,'actual mapped FF fault anchor '+target)
    match=matches[0];cell=match[0]
    if fault=='clock':changed=cell.replace('.CP(i_clk)','.CP(i_ready)')
    else:changed=re.sub(r'\.D\([^()]+\)',f'.D({"i_source_control[1]" if fault=="capture" else "i_source_valid"})',cell)
    return source[:match.start()]+changed+source[match.end():]


def interface(graph,width):
    inputs=dict(i_clk=1,i_rstn=1,i_source_valid=1,i_ready=1,i_done=1,i_response=1,i_auth=1,i_shared=1,i_source_control=256,i_source_tags=512,i_capacity=20*(width+1))
    for direction,expected in (('input',inputs),('output',OUTPUTS)):
        need({n:len(p['bits']) for n,p in graph['ports'].items() if p['direction']==direction}==expected,'complete original '+direction+' interface')
    return inputs


def step_text(width,layouts,case):
    layout=layouts['gold'];need(layout['aliases']==layouts['gate']['aliases'],'semantic alias/state order differs')
    count=layout['state_bits'];need(count==layouts['gate']['state_bits'],'actual state size differs')
    aliases=layout['aliases'];owner=aliases['r_owned'][0];cursor=aliases['r_cursor']
    need(isinstance(owner,int) and all(isinstance(x,int) for x in cursor),'ownership/cursor must be real state')
    inputs=dict(i_clk=1,i_source_valid=1,i_ready=1,i_done=1,i_response=1,i_auth=1,i_shared=1,i_source_control=256,i_source_tags=512,i_capacity=20*(width+1))
    inputs.update(h_state=count,e_gold=count,e_gate=count)
    declarations=','.join(f'input wire [{b-1}:0] {n}' for n,b in inputs.items())
    code=[f'module step({declarations},output wire o_bad);']
    next_cursor=[]
    for side in ('gold','gate'):
        code += [f'wire [{count-1}:0] {side}_state,{side}_next;wire [530:0] {side}_outputs;']
        for index in range(count):
            value=f'e_{side}[{index}]'
            if case=='owned':value="1'b1" if index==owner else f'h_state[{index}]'
            elif case=='empty' and index in (owner,*cursor):value="1'b0"
            code += [f'assign {side}_state[{index}]={value};']
        con=[f'.{n}({n})' for n in inputs if n not in ('h_state','e_gold','e_gate')]
        con += [f".i_rstn(1'b{0 if case=='reset' else 1})",f'.s_state({side}_state)',f'.n_state({side}_next)']
        shift=0
        for name,bits in OUTPUTS.items():con.append(f'.{name}({side}_outputs[{shift}+:{bits}])');shift+=bits
        con += [f'.{name}()' for name in FIELDS]
        code += [f'step_{side} {side}('+','.join(con)+');']
        next_cursor.append('{'+','.join(f'{side}_next[{i}]' for i in reversed(cursor))+'}')
    next_owner=f'(gold_next[{owner}]!=gate_next[{owner}])'
    next_difference=f'{next_owner}||({next_cursor[0]}!={next_cursor[1]})||(gold_next[{owner}]&&(|(gold_next^gate_next)))'
    if case=='reset':
        bad=f'(|gold_outputs)||(|gate_outputs)||gold_next[{owner}]||gate_next[{owner}]||(|{next_cursor[0]})||(|{next_cursor[1]})'
    else:bad=f'(|(gold_outputs^gate_outputs))||{next_difference}'
    code += ['assign o_bad='+bad+';','endmodule']
    return '\n'.join(code)+'\n'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label',default='mapped');parser.add_argument('--widths',type=int,nargs='+',choices=(8,16),default=[8,16])
    parser.add_argument('--timing-root',type=Path,default=ROOT/'build/verification/tl_prepared_partition/timing')
    parser.add_argument('--seconds',type=int,default=180)
    parser.add_argument('--candidate',type=Path,default=ROOT/'rtl/tl/tl_prepared_partition.v',help='exact candidate used by the selected timing run')
    parser.add_argument('--cases',nargs='+',choices=('reset','empty','owned'),default=['reset','empty','owned'],help='explicit local obligations; complete CEC can supply the owned-state step')
    parser.add_argument('--fault',choices=('clock','reset','capture','output'),help='mutate one actual mapped cell; no healthy equivalence claim')
    parser.add_argument('--prepare-only',action='store_true',help='retain exact observations/cuts for separate complete CEC and reset checks')
    args=parser.parse_args();need(args.label.replace('_','').replace('-','').isalnum() and args.seconds>0 and len(set(args.widths))==len(args.widths),'invalid run matrix')
    timing=args.timing_root.resolve();mapping=json.loads((timing/'results.json').read_text())
    candidate=args.candidate.resolve()
    need(mapping['complete'] and mapping['sources_unchanged'] and sha(candidate)==mapping['candidate_sha256'],'current mapped candidate identity')
    for name,digest in mapping['sources'].items():need(sha(ROOT/name)==digest,'mapped source identity '+name)
    library=Path(mapping['libraries']['ssg0p81v125c']['path']);need(sha(library)==mapping['libraries']['ssg0p81v125c']['sha256'],'actual Liberty identity')
    stage=ROOT/'build/verification/tl_prepared_mapping'/args.label;stage.mkdir(parents=True,exist_ok=False)
    sources=[candidate,ROOT/'rtl/tl/tl_control_decode.v',ROOT/'rtl/tl/tl_control_tenure.v']
    for source in sources:(stage/source.name).write_bytes(source.read_bytes())
    for name in ('run_mapped.py','mapped_state.py'):(stage/name).write_bytes(Path(__file__).with_name(name).read_bytes())
    result=dict(complete=False,scope='conditional full output/actual next-state relation; reset and constant-state composition required',sources={str(p):sha(p) for p in sources},timing_report_sha256=sha(timing/'results.json'),library=dict(path=str(library),sha256=sha(library)),public_output_bits=531,requested_widths=args.widths,cases_requested=args.cases,fault=args.fault,prepare_only=args.prepare_only,results=[])
    for width in args.widths:
        folder=stage/f'w{width}';folder.mkdir();mapped=timing/f'width{width}/mapped.v'
        record=next(r for r in mapping['widths'] if r['width']==width)
        need(record['mapping']['exit']==0 and sha(mapped)==record['netlist_sha256'],'actual STA netlist identity')
        (folder/'mapped.v').write_text(mutate_netlist(mapped.read_text(),args.fault));script=[]
        for side in ('gold','gate'):
            script+=['yosys design -reset']
            if side=='gate':script += [f'yosys read_liberty -ignore_miss_func {{{library}}}',f'yosys read_verilog {{{folder}/mapped.v}}']
            else:
                script += [f'yosys read_verilog {{{stage/source.name}}}' for source in sources]
                script += [f'yosys chparam -set WIDTH {width} tl_prepared_partition']
            script += ['yosys prep -top tl_prepared_partition -flatten',f'yosys write_json {{{folder}/{side}_original.json}}','yosys expose tl_prepared_partition/w:r_*','yosys techmap','yosys opt -full','yosys dffunmap','yosys opt_clean -purge','yosys check -assert',f'yosys write_json {{{folder}/{side}_observed.json}}']
        (folder/'prepare.tcl').write_text('\n'.join(script)+'\n')
        prepared=execute(['yosys','-Q','-T','-c',str(folder/'prepare.tcl')],folder/'prepare.log',180)
        row=dict(width=width,netlist_sha256=sha(folder/'mapped.v'),healthy_netlist_sha256=sha(mapped),prepare=prepared,cases=[],passed=False);result['results'].append(row);dump(stage/'results.json',result)
        if prepared['exit']:continue
        layouts={}
        for side in ('gold','gate'):
            original=json.loads((folder/f'{side}_original.json').read_text())['modules']['tl_prepared_partition'];interface(original,width)
            graph=json.loads((folder/f'{side}_observed.json').read_text())['modules']['tl_prepared_partition']
            need(set(graph['ports'])==set(original['ports'])|set(FIELDS),'unexpected observation port')
            try:cut,layout=observe(graph,FIELDS)
            except ValueError as error:
                row['inventory_error']=str(error);dump(stage/'results.json',result);break
            cut.get('attributes',{}).pop('top',None)
            dump(folder/f'{side}_cut.json',dict(modules={'step_'+side:cut}));dump(folder/f'{side}_state.json',layout);layouts[side]=layout
        if 'inventory_error' in row:continue
        row['state_bits']={s:l['state_bits'] for s,l in layouts.items()};row['prepared']=True;dump(stage/'results.json',result)
        if args.prepare_only:continue
        for case in args.cases:
            proof_dir=folder/case;proof_dir.mkdir();(proof_dir/'step.v').write_text(step_text(width,layouts,case))
            script=f'read_json "{folder}/gold_cut.json" "{folder}/gate_cut.json"\nread_verilog "{proof_dir}/step.v"\nprep -top step -flatten\nopt -full\ncheck -assert\nwrite_json "{proof_dir}/step.json"\nsat -prove o_bad 0 -verify -dump_json "{proof_dir}/witness.json"\n'
            (proof_dir/'proof.ys').write_text(script)
            proof=execute(['yosys','-Q','-T','-s',str(proof_dir/'proof.ys')],proof_dir/'proof.log',args.seconds)
            passed=proof['exit']==0 and 'SAT proof finished - no model found: SUCCESS!' in (proof_dir/'proof.log').read_text()
            row['cases'].append(dict(case=case,proof=proof,passed=passed));dump(stage/'results.json',result);print(width,case,passed,proof,flush=True)
        row['passed']=len(row['cases'])==len(args.cases) and all(r['passed'] for r in row['cases']);dump(stage/'results.json',result)
    result['complete']=len(result['results'])==len(args.widths) and all(r['passed'] for r in result['results']);dump(stage/'results.json',result)
    return 0 if result['complete'] or (args.prepare_only and all(r.get('prepared') for r in result['results'])) else 1


if __name__=='__main__':raise SystemExit(main())

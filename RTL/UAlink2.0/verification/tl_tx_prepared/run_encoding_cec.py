"""Run python3 verification/tl_tx_prepared/run_encoding_cec.py --label encoded_step
[--pair mapped_pair] [--physical physical_baseline] [--widths 8 16].
Use --prepare-only to emit complete raw/pruned graphs for run_partitioned_cec.py
without running the monolithic CEC; preparation never claims equivalence.
Compare all public/macro outputs and every actual next-state bit under an
explicit binary/one-hot cursor relation extracted from the actual mapping log.
Outputs source-bound relation, wrapper BLIF and ABC CEC evidence. Next prove
reset/dormant-state establishment and qualify actual mapped-cell mutations;
conditional CEC is not yet complete post-reset mapped equivalence.
"""
from pathlib import Path
import argparse
import json
import re
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha,prune_dead_names


def identifier(name):
    return name if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',name) else '\\'+name+' '


def relation(gold,gate,log):
    ga,ma=gold['aliases'],gate['aliases'];need(set(ga)==set(ma),'field set changed')
    cursors={f'gen_prepare[{lane}].Prepare_Inst.r_cursor' for lane in (0,1)}
    mapping={};encodings={}
    for field in ga:
        if field in cursors:
            need(len(ga[field])==4 and len(ma[field])==9 and all(type(x)==int for x in ga[field]+ma[field]),'unexpected cursor storage')
            header=rf"Recoding FSM `[^\n]*{re.escape(field)}[^\n]*\n\s+mapping auto encoding to `one-hot` for this FSM\.\n((?:\s+[01]{{4}} -> [-1]{{9}}\n)+)"
            found=re.findall(header,log);need(len(found)==1,'missing actual synthesis encoding table')
            rows=re.findall(r'([01]{4}) -> ([-1]{9})',found[0]);table={int(a,2):int(b.replace('-','0'),2) for a,b in rows}
            need(set(table)==set(range(9)) and len(rows)==9 and set(table.values())=={1<<i for i in range(9)},'incomplete one-hot codebook')
            encodings[field]=table
            continue
        need(len(ga[field])==len(ma[field]),'noncursor field width mismatch')
        for old,new in zip(ga[field],ma[field]):
            if type(new)==int:
                need(type(old)==int,'noncursor state lost');need(new not in mapping or mapping[new]==old,'inconsistent alias state relation');mapping[new]=old
            else:need(old==new,'noncursor constant changed')
    extra={b for field in cursors for b in ma[field]}
    need(set(mapping)|extra==set(range(gate['state_bits'])) and not(set(mapping)&extra),'unmapped actual gate state')
    need(set(mapping.values())|{b for field in cursors for b in ga[field]}==set(range(gold['state_bits'])),'unmapped actual gold state')
    return dict(non_cursor_gate_to_gold=mapping,cursor_encodings=encodings,gold_state_bits=gold['state_bits'],gate_state_bits=gate['state_bits'])


def wrapper(side,ports,gold,gate,rel):
    inputs={n:p for n,p in ports.items() if p['direction']=='input' and n!='s_state'}
    outputs={n:p for n,p in ports.items() if p['direction']=='output' and n!='n_state'}
    ng=gold['state_bits'];nm=gate['state_bits'];own=ng if side=='gold' else nm
    declarations=[f'input wire [{len(p["bits"])-1}:0] {identifier(n)}' for n,p in inputs.items()]
    declarations += [f'input wire [{ng-1}:0] h_state',f'output wire [{nm-1}:0] c_next']
    declarations += [f'output wire [{len(p["bits"])-1}:0] {identifier(n)}' for n,p in outputs.items()]
    code=['module case_'+side+'('+',\n'.join(declarations)+');',f'wire [{own-1}:0] actual_state,actual_next;',f'wire [{nm-1}:0] related_next;']
    guard=[]
    for field,table in rel['cursor_encodings'].items():
        current='{'+','.join(f'h_state[{x}]' for x in reversed(gold['aliases'][field]))+'}'
        guard.append(f'({current}<=4\'d8)')
    code+=['wire legal_cursor;assign legal_cursor='+'&&'.join(guard)+';']
    if side=='gold':code+=['assign actual_state=h_state;']
    for index,old in rel['non_cursor_gate_to_gold'].items():
        if side=='gate':code.append(f'assign actual_state[{index}]=h_state[{old}];')
        code.append(f'assign related_next[{index}]=actual_next[{old if side=="gold" else index}];')
    for field,table in rel['cursor_encodings'].items():
        current='{'+','.join(f'h_state[{x}]' for x in reversed(gold['aliases'][field]))+'}'
        nxt='{'+','.join(f'actual_next[{x}]' for x in reversed(gold['aliases'][field]))+'}'
        for binary,hot in table.items():
            index=gate['aliases'][field][hot.bit_length()-1]
            if side=='gate':code.append(f"assign actual_state[{index}]=({current}==4'd{binary});")
            code.append(f'assign related_next[{index}]='+ (f"({nxt}==4'd{binary});" if side=='gold' else f'actual_next[{index}];'))
    con=[f'.{identifier(n)}({identifier(n)})' for n in inputs]
    con += ['.s_state(actual_state)','.n_state(actual_next)']
    for number,(name,port) in enumerate(outputs.items()):
        bits=len(port['bits']);code.append(f'wire [{bits-1}:0] raw_{number};')
        code.append(f"assign {identifier(name)}=legal_cursor?raw_{number}:{bits}'d0;")
        con.append(f'.{identifier(name)}(raw_{number})')
    code += [f'step_{side} actual('+',\n'.join(con)+');',f"assign c_next=legal_cursor?related_next:{nm}'d0;",'endmodule']
    return '\n'.join(code)+'\n'


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--pair',default='mapped_pair');p.add_argument('--physical',default='physical_baseline');p.add_argument('--widths',type=int,nargs='+',choices=(8,16),default=[8,16]);p.add_argument('--prepare-only',action='store_true');a=p.parse_args()
    for name in (a.label,a.pair,a.physical):need(name.replace('_','').replace('-','').isalnum(),'invalid label')
    base=ROOT/'build/verification/tl_tx_prepared';stage=base/a.label;stage.mkdir(exist_ok=False);(stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    result=dict(complete=False,scope='conditional complete outputs and actual encoded next-state CEC; both binary cursors in 0..8',results=[],reset_relation=False,dormant_relation=False,actual_fault_qualified=False,mapped_equivalence=False,full_goal_complete=False)
    for width in a.widths:
        source=base/a.pair/f'w{width}';folder=stage/f'w{width}';folder.mkdir();layouts={s:json.loads((source/f'{s}_state.json').read_text()) for s in ('gold','gate')}
        log=base/a.physical/f'w{width}/map.log';rel=relation(layouts['gold'],layouts['gate'],log.read_text());dump(folder/'relation.json',rel)
        row=dict(width=width,sources={str(p):sha(p) for p in [log]+[source/(s+n) for s in ('gold','gate') for n in ('_state.json','_cut.json')]},emissions=[],equivalent=False)
        result['results'].append(row);dump(stage/'results.json',result)
        for side in ('gold','gate'):
            graph=json.loads((source/f'{side}_cut.json').read_text())['modules']['step_'+side]
            (folder/f'{side}.sv').write_text(wrapper(side,graph['ports'],layouts['gold'],layouts['gate'],rel))
            script=f'read_json "{source}/{side}_cut.json"\nread_verilog "{folder}/{side}.sv"\nprep -top case_{side} -flatten\ntechmap\nopt -full\ncheck -assert\nwrite_json "{folder}/{side}.json"\nwrite_blif "{folder}/{side}.blif"\n'
            (folder/f'{side}.ys').write_text(script);run=execute(['yosys','-Q','-T','-s',str(folder/f'{side}.ys')],folder/f'{side}.log',120);row['emissions'].append(run);dump(stage/'results.json',result);need(run['exit']==0,'wrapper emission failed')
            pruned,audit=prune_dead_names((folder/f'{side}.blif').read_text())
            (folder/f'{side}_pruned.blif').write_text(pruned);dump(folder/f'{side}_prune.json',audit)
        row['prepared']=True
        if a.prepare_only:
            dump(stage/'results.json',result);print(width,'prepared; equivalence not yet proved',flush=True)
            continue
        command=f'cec -T 120 -v "{folder}/gold_pruned.blif" "{folder}/gate_pruned.blif"';(folder/'cec_command.txt').write_text(command+'\n')
        row['cec']=execute(['yosys-abc','-c',command],folder/'cec.log',150);text=(folder/'cec.log').read_text();row['equivalent']=row['cec']['exit']==0 and text.count('Networks are equivalent.')==1
        dump(stage/'results.json',result);print(width,row['equivalent'],row['cec'],flush=True)
    result['preparation_complete']=len(result['results'])==len(a.widths) and all(r.get('prepared') for r in result['results'])
    result['complete']=len(result['results'])==len(a.widths) and all(r['equivalent'] for r in result['results']);dump(stage/'results.json',result);return 0 if result['complete'] or (a.prepare_only and result['preparation_complete']) else 1


if __name__=='__main__':raise SystemExit(main())

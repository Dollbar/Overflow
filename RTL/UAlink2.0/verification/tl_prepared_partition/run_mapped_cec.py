"""Run: python3 verification/tl_prepared_partition/run_mapped_cec.py
--parent actual_relation --label complete_cec [--widths 8 16]. Checks ALL
original outputs and actual FF next-state equations under a common full state,
using ABC CEC. Inputs are real cut graphs already inventoried by run_mapped.py;
outputs include full BLIFs, naming inventories, pruning records and CEC logs.
Next combine with independent reset/empty proofs and audit real mapped faults.
"""
from pathlib import Path
import argparse
import json
import re
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha,prune_dead_names


def port_names(name,port):
    width=len(port['bits']);offset=port.get('offset',0)
    return [name] if width==1 and not offset else [f'{name}[{offset+i}]' for i in range(width)]


def declarations(raw,directive):
    text=raw.replace('\\\n',' ')
    lines=[x.split()[1:] for x in text.splitlines() if x.startswith(directive+' ')]
    need(len(lines)==1,'one BLIF declaration required '+directive)
    need(len(lines[0])==len(set(lines[0])),'duplicate BLIF port')
    return lines[0]


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parent',required=True);p.add_argument('--label',required=True)
    p.add_argument('--widths',type=int,nargs='+',choices=range(8,17),default=[8,16])
    p.add_argument('--base',type=Path,default=ROOT/'build/verification/tl_prepared_mapping',help='alternate prepared RTL-pair artifact root')
    a=p.parse_args()
    for label in (a.parent,a.label):need(label.replace('_','').replace('-','').isalnum(),'invalid label')
    need(len(set(a.widths))==len(a.widths),'duplicate width')
    base=a.base.resolve();parent=base/a.parent;stage=base/a.label;stage.mkdir(exist_ok=False)
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    report=json.loads((parent/'results.json').read_text())
    result=dict(complete=False,parent=a.parent,source_identity=report['sources'],library=report['library'],public_output_bits=531,scope='all binary state values: all original outputs and all actual FF next-state bits; reset/empty composition required',results=[])
    for width in a.widths:
        folder=stage/f'w{width}';folder.mkdir();source=parent/f'w{width}';scripts=[];layouts={};graphs={}
        for side in ('gold','gate'):
            graph=json.loads((source/f'{side}_cut.json').read_text())['modules']['step_'+side];graphs[side]=graph
            layouts[side]=json.loads((source/f'{side}_state.json').read_text())
            need(not any('DFF' in c['type'] or 'latch' in c['type'].lower() for c in graph['cells'].values()),'cut contains sequential cell')
            scripts+=['yosys design -reset',f'yosys read_json {{{source}/{side}_cut.json}}',f'yosys hierarchy -top step_{side}','yosys check -assert',f'yosys write_blif {{{folder}/{side}.blif}}']
        need(layouts['gold']['aliases']==layouts['gate']['aliases'],'full semantic state correspondence')
        (folder/'prepare.tcl').write_text('\n'.join(scripts)+'\n')
        prepared=execute(['yosys','-Q','-T','-c',str(folder/'prepare.tcl')],folder/'prepare.log',60)
        row=dict(width=width,prepare=prepared,parent_hashes={n:sha(source/n) for n in ('mapped.v','gold_observed.json','gate_observed.json','gold_cut.json','gate_cut.json','gold_state.json','gate_state.json')},equivalent=False)
        result['results'].append(row);dump(stage/'results.json',result);need(prepared['exit']==0,'actual BLIF preparation')
        names={}
        for side in ('gold','gate'):
            raw=(folder/f'{side}.blif').read_text();need(not re.search(r'^\.(latch|gate|subckt|blackbox)\b',raw,re.M),'unexpanded BLIF primitive')
            live,pruned=prune_dead_names(raw);(folder/f'{side}_live.blif').write_text(live);dump(folder/f'{side}_prune.json',pruned)
            names[side]={}
            for direction,directive in (('input','.inputs'),('output','.outputs')):
                expected={bit for name,port in graphs[side]['ports'].items() if port['direction']==direction for bit in port_names(name,port)}
                declared=declarations(live,directive);need(set(declared)==expected,'all real BLIF '+direction+' ports');names[side][direction]=declared
        need(names['gold']==names['gate'],'exact named CEC input/output correspondence')
        dump(folder/'ports.json',names)
        row.update(actual_next_state_bits=layouts['gold']['state_bits'],cec_input_bits=len(names['gold']['input']),cec_output_bits=len(names['gold']['output']))
        command=f'cec -T 120 -v "{folder}/gold_live.blif" "{folder}/gate_live.blif"';(folder/'command.txt').write_text(command+'\n')
        proof=execute(['yosys-abc','-c',command],folder/'proof.log',150);log=(folder/'proof.log').read_text()
        row.update(proof=proof,equivalent=proof['exit']==0 and log.count('Networks are equivalent.')==1 and not re.search(r'Warning:|Error:|ERROR:',log),actual_mismatch=proof['exit']==0 and 'Networks are NOT EQUIVALENT.' in log)
        dump(stage/'results.json',result);print(width,row['equivalent'],row['actual_mismatch'],proof,flush=True)
    result['complete']=len(result['results'])==len(a.widths) and all(r['equivalent'] for r in result['results']);dump(stage/'results.json',result)
    return 0 if result['complete'] else 1


if __name__=='__main__':raise SystemExit(main())

"""Run python3 verification/tl_tx_prepared/run_mapped_pair.py --label mapped_pair
[--physical physical_baseline] [--widths 8 16]. Requires completed mappings,
not closed STA. Outputs complete actual D/Q graphs and macro transaction ports.
Next complete-state CEC plus reset/dormant-state obligations; preparation alone
does not prove mapped equivalence or any full protocol/physical signoff.
"""
from pathlib import Path
import argparse
import json
import re
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
sys.path.insert(0,str(ROOT/'verification/tl_prepared_partition'))
from run_cec import dump,execute,need,sha
from mapped_state import observe,audit_cut


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--physical',default='physical_baseline');p.add_argument('--widths',type=int,nargs='+',choices=(8,16),default=[8,16]);a=p.parse_args()
    for name in (a.label,a.physical):need(name.replace('_','').replace('-','').isalnum(),'invalid label')
    base=ROOT/'build/verification/tl_tx_prepared';physical=base/a.physical;stage=base/a.label;stage.mkdir(exist_ok=False)
    record=json.loads((physical/'results.json').read_text());library=Path(record['libraries']['ssg0p81v125c']['path'])
    need(sha(library)==record['libraries']['ssg0p81v125c']['sha256'],'library changed')
    for name,digest in record['sources'].items():need(sha(Path(name))==digest,'source changed')
    original_sources=[Path(n) for n in record['sources'] if Path(n).is_relative_to(ROOT/'rtl')]
    deps=[Path(n) for n in record['sources'] if Path(n).name in ('kd28_sram_blackboxes.v','kd28_fifo_sdp_storage_map.v')]
    blackbox=next(x for x in deps if x.name=='kd28_sram_blackboxes.v');mapping=next(x for x in deps if x.name!='kd28_sram_blackboxes.v')
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    result=dict(complete=False,scope='actual full-state/macro transaction pair preparation only',sources=record['sources'],library=record['libraries']['ssg0p81v125c'],results=[],mapped_equivalence=False,full_goal_complete=False)
    for width in a.widths:
        folder=stage/f'w{width}';folder.mkdir();mapped=physical/f'w{width}/mapped.v'
        row=next(x for x in record['results'] if x['width']==width)
        need(row['mapping']['exit']==0 and sha(mapped)==row['netlist_sha256'],'actual mapped identity')
        (folder/'mapped.v').write_bytes(mapped.read_bytes())
        script=[]
        for side in ('gold','gate'):
            script+=['yosys design -reset',f'yosys read_verilog -lib {{{blackbox}}}']
            if side=='gold':
                script+=[f'yosys read_verilog {{{x}}}' for x in [mapping]+[physical/'sources'/x.name for x in original_sources]]
                script += [f'yosys chparam -set WIDTH {width} -set HEADER_DEPTH 2 -set BANK_DEPTH 3 tl_tx_prepared']
            else:script += [f'yosys read_liberty -ignore_miss_func {{{library}}}',f'yosys read_verilog {{{folder}/mapped.v}}']
            script += ['yosys prep -top tl_tx_prepared -flatten',f'yosys write_json {{{folder}/{side}_original.json}}',
                       'yosys select -assert-count 64 tl_tx_prepared/t:KD28_SRAM_SDP_256X32',
                       'yosys expose -evert tl_tx_prepared/t:KD28_SRAM_*',
                       'yosys techmap','yosys opt -full','yosys dffunmap','yosys opt_clean','yosys check -assert',
                       f'yosys write_json {{{folder}/{side}_observed.json}}']
        (folder/'prepare.tcl').write_text('\n'.join(script)+'\n')
        item=dict(width=width,netlist_sha256=sha(mapped),prepare=execute(['yosys','-Q','-T','-c',str(folder/'prepare.tcl')],folder/'prepare.log',240),prepared=False)
        result['results'].append(item);dump(stage/'results.json',result)
        if item['prepare']['exit']:continue
        graphs={side:json.loads((folder/f'{side}_observed.json').read_text())['modules']['tl_tx_prepared'] for side in ('gold','gate')}
        fields={};layouts={}
        try:
            for side,graph in graphs.items():
                qs={b for c in graph['cells'].values() if c['type']=='$_DFF_P_' for b in c['connections']['Q']}
                fields[side]=sorted(n for n,wire in graph['netnames'].items() if not wire.get('hide_name') and re.search(r'(?:^|\.)(?:r_|reg_|cnt_|read_bank_q)',n) and any(b in qs for b in wire['bits']) and all(b in qs or b in ('0','1') for b in wire['bits']))
            need(fields['gold']==fields['gate'],'semantic register field set differs')
            for side,graph in graphs.items():
                cut,layout=observe(graph,fields[side]);audit_cut(graph,cut,layout);cut['attributes'].pop('top',None)
                dump(folder/f'{side}_cut.json',dict(modules={f'step_{side}':cut}));dump(folder/f'{side}_state.json',layout);layouts[side]=layout
            need(layouts['gold']['aliases']==layouts['gate']['aliases'],'actual state/constant correspondence differs')
            need({n:(x['direction'],len(x['bits'])) for n,x in graphs['gold']['ports'].items()}=={n:(x['direction'],len(x['bits'])) for n,x in graphs['gate']['ports'].items()},'full public/macro port inventory differs')
            item.update(prepared=True,state_bits=layouts['gold']['state_bits'],semantic_fields=len(fields['gold']),inputs=sum(len(x['bits']) for x in graphs['gold']['ports'].values() if x['direction']=='input'),outputs=sum(len(x['bits']) for x in graphs['gold']['ports'].values() if x['direction']=='output'))
        except ValueError as error:item['inventory_error']=str(error)
        dump(stage/'results.json',result);print(item,flush=True)
    result['complete']=len(result['results'])==len(a.widths) and all(x['prepared'] for x in result['results']);dump(stage/'results.json',result)
    return 0 if result['complete'] else 1


if __name__=='__main__':raise SystemExit(main())

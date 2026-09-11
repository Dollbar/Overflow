"""Run: python3 verification/tl_prepared_partition/run_selection_equivalence.py
--candidate FILE --label rtl_pair [--widths 8 ... 16]. Prepares complete actual
RTL state/port graphs against immutable 8bf4afc production RTL; no state or public
output is discarded. Outputs under build/verification/tl_selection_reduction.
Next run run_mapped_cec.py --base build/verification/tl_selection_reduction
--parent rtl_pair --label rtl_cec --widths 8 9 10 11 12 13 14 15 16.
"""
from pathlib import Path
import argparse
import json
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha
from run_mapped import FIELDS,interface
from mapped_state import observe,audit_cut

REFERENCE='8bf4afcd54eaec3bc4ac35811fd6266b4ba86e61'


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--candidate',type=Path,required=True);p.add_argument('--label',default='rtl_pair')
    p.add_argument('--widths',type=int,nargs='+',choices=range(8,17),default=list(range(8,17)));a=p.parse_args()
    need(a.label.replace('_','').replace('-','').isalnum() and len(set(a.widths))==len(a.widths),'invalid run matrix')
    stage=ROOT/'build/verification/tl_selection_reduction'/a.label;stage.mkdir(parents=True,exist_ok=False)
    (stage/'candidate.v').write_bytes(a.candidate.read_bytes())
    for name in ('tl_prepared_partition.v','tl_control_decode.v','tl_control_tenure.v'):
        (stage/name).write_bytes(subprocess.check_output(['git','show',REFERENCE+':rtl/tl/'+name],cwd=ROOT))
    for name in ('tl_control_decode.v','tl_control_tenure.v'):need((stage/name).read_bytes()==(ROOT/'rtl/tl'/name).read_bytes(),'unchanged decoder dependency')
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    result=dict(complete=False,reference=REFERENCE,sources={str(a.candidate.resolve()):sha(a.candidate)},library=None,mode='rtl_pair',results=[])
    for width in a.widths:
        folder=stage/f'w{width}';folder.mkdir();scripts=[]
        for side in ('gold','gate'):
            scripts+=['yosys design -reset']
            for name in (('tl_prepared_partition.v' if side=='gold' else 'candidate.v'),'tl_control_decode.v','tl_control_tenure.v'):
                scripts.append(f'yosys read_verilog {{{stage/name}}}')
            scripts += [f'yosys chparam -set WIDTH {width} tl_prepared_partition','yosys prep -top tl_prepared_partition -flatten',f'yosys write_json {{{folder}/{side}_original.json}}','yosys expose tl_prepared_partition/w:r_*','yosys techmap','yosys opt -full','yosys dffunmap','yosys opt_clean -purge','yosys check -assert',f'yosys write_json {{{folder}/{side}_observed.json}}']
        (folder/'prepare.tcl').write_text('\n'.join(scripts)+'\n')
        prepared=execute(['yosys','-Q','-T','-c',str(folder/'prepare.tcl')],folder/'prepare.log',120)
        row=dict(width=width,prepare=prepared,passed=False);result['results'].append(row);dump(stage/'results.json',result)
        if prepared['exit']:continue
        layouts={}
        for side in ('gold','gate'):
            graph=json.loads((folder/f'{side}_original.json').read_text())['modules']['tl_prepared_partition'];interface(graph,width)
            graph=json.loads((folder/f'{side}_observed.json').read_text())['modules']['tl_prepared_partition'];cut,layout=observe(graph,FIELDS)
            audit_cut(graph,cut,layout);cut.get('attributes',{}).pop('top',None);layouts[side]=layout
            dump(folder/f'{side}_cut.json',dict(modules={'step_'+side:cut}));dump(folder/f'{side}_state.json',layout)
        need(layouts['gold']['aliases']==layouts['gate']['aliases'],'complete semantic state pairing')
        # The shared CEC runner snapshots a generic candidate artifact in this slot.
        (folder/'mapped.v').write_bytes(a.candidate.read_bytes())
        row.update(passed=True,state_bits=layouts['gold']['state_bits']);dump(stage/'results.json',result);print(width,'prepared',row['state_bits'],flush=True)
    result['complete']=len(result['results'])==len(a.widths) and all(r['passed'] for r in result['results']);dump(stage/'results.json',result)
    return 0 if result['complete'] else 1


if __name__=='__main__':raise SystemExit(main())

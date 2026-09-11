"""Run: python3 verification/tl_prepared_partition/run_state_cases.py
--base build/verification/tl_selection_reduction --parent direct_pair
--label direct_reset --widths 8 16. Proves independent-state reset and empty/
capture relations using already inventoried actual RTL D/Q graphs. Outputs full
step source, optimized graph, SAT logs and witnesses. Next combine with complete
state CEC for post-reset sequential equivalence; no owned payload equality is
assumed before an actual capture.
"""
from pathlib import Path
import argparse
import json
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha
from run_mapped import step_text
from mapped_state import audit_cut


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--base',type=Path,required=True);p.add_argument('--parent',required=True);p.add_argument('--label',required=True)
    p.add_argument('--widths',type=int,nargs='+',choices=range(8,17),required=True);a=p.parse_args()
    for name in (a.parent,a.label):need(name.replace('_','').replace('-','').isalnum(),'invalid label')
    need(len(set(a.widths))==len(a.widths),'duplicate width');base=a.base.resolve();parent=base/a.parent;stage=base/a.label;stage.mkdir(exist_ok=False)
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes());result=dict(complete=False,parent=a.parent,results=[])
    for width in a.widths:
        source=parent/f'w{width}';folder=stage/f'w{width}';folder.mkdir();layouts={}
        for side in ('gold','gate'):
            layouts[side]=json.loads((source/f'{side}_state.json').read_text())
            graph=json.loads((source/f'{side}_observed.json').read_text())['modules']['tl_prepared_partition']
            cut=json.loads((source/f'{side}_cut.json').read_text())['modules']['step_'+side];audit_cut(graph,cut,layouts[side])
        hashes={n:sha(source/n) for n in ('gold_cut.json','gate_cut.json','gold_state.json','gate_state.json')}
        for case in ('reset','empty'):
            b=folder/case;b.mkdir();(b/'step.v').write_text(step_text(width,layouts,case))
            script=f'read_json "{source}/gold_cut.json" "{source}/gate_cut.json"\nread_verilog "{b}/step.v"\nprep -top step -flatten\nopt -full\ncheck -assert\nwrite_json "{b}/step.json"\nsat -prove o_bad 0 -verify -dump_json "{b}/witness.json"\n';(b/'proof.ys').write_text(script)
            proof=execute(['yosys','-Q','-T','-s',str(b/'proof.ys')],b/'proof.log',90);passed=proof['exit']==0 and 'SAT proof finished - no model found: SUCCESS!' in (b/'proof.log').read_text()
            result['results'].append(dict(width=width,case=case,source_hashes=hashes,proof=proof,passed=passed));dump(stage/'results.json',result);print(width,case,passed,proof,flush=True)
    result['complete']=len(result['results'])==2*len(a.widths) and all(r['passed'] for r in result['results']);dump(stage/'results.json',result)
    return 0 if result['complete'] else 1


if __name__=='__main__':raise SystemExit(main())

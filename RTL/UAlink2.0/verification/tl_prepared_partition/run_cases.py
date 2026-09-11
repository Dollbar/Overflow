"""Run python3 verification/tl_prepared_partition/run_cases.py --step-label NAME
[--label cases] [--widths 8 16]. Checks reset with every state independent, empty
ownership, and all eight possible owned cursor values by cofactoring true primary
inputs before optimization. Emits exact cofactor graphs/logs/witnesses. Next join
all ten cases per width with the proved metadata/ownership/cursor invariants.
No input derived from a decoder is replaced or assumed independently.
"""
from pathlib import Path
import argparse
import copy
import json
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha

CASES=[('reset',dict(i_rstn=0)),('empty',dict(i_rstn=1,h_owned=0,h_cursor=0))]+[(f'owned_{n}',dict(i_rstn=1,h_owned=1,h_cursor=n)) for n in range(8)]


def cofactor(source,fixed):
    graph=copy.deepcopy(source);module=graph['modules']['step'];substitution={}
    for name,value in fixed.items():
        port=module['ports'][name];need(port['direction']=='input' and 0<=value<(1<<len(port['bits'])),'cofactor is not a valid primary input value')
        for index,bit in enumerate(port['bits']):
            need(isinstance(bit,int) and bit not in substitution,'cofactor input alias')
            substitution[bit]=str((value>>index)&1)
        del module['ports'][name]
    def mapped(bits):return [substitution.get(b,b) for b in bits]
    for port in module['ports'].values():port['bits']=mapped(port['bits'])
    for net in module['netnames'].values():net['bits']=mapped(net['bits'])
    for cell in module['cells'].values():
        for name,bits in cell['connections'].items():cell['connections'][name]=mapped(bits)
    return graph


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--step-label',required=True);parser.add_argument('--label',default='cases')
    parser.add_argument('--widths',type=int,nargs='+',choices=range(8,17),default=[8,16])
    args=parser.parse_args()
    for name in (args.step_label,args.label):need(name.replace('_','').replace('-','').isalnum(),'invalid label')
    base=ROOT/'build/verification/tl_prepared_equivalence';stage=base/args.label;stage.mkdir(parents=True,exist_ok=False)
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    parent=base/args.step_label
    result=dict(complete=False,step_label=args.step_label,step_report_sha256=sha(parent/'results.json'),scope='complete conditional output/next-state theorem; reachable invariant composition required',results=[])
    for width in args.widths:
        source=parent/f'w{width}'/'step_structure.json';graph=json.loads(source.read_text())
        folder=stage/f'w{width}';folder.mkdir()
        for name,fixed in CASES:
            case=folder/name;case.mkdir();dump(case/'cofactor.json',cofactor(graph,fixed))
            script=f'read_json "{case}/cofactor.json"\nopt -full\ncheck -assert\nsat -prove o_bad 0 -verify -dump_json "{case}/witness.json"\n'
            (case/'proof.ys').write_text(script)
            proof=execute(['yosys','-Q','-T','-s',str(case/'proof.ys')],case/'proof.log',120)
            log=(case/'proof.log').read_text();row=dict(width=width,case=name,fixed=fixed,source_sha256=sha(source),cofactor_sha256=sha(case/'cofactor.json'),proof=proof,passed=proof['exit']==0 and 'SAT proof finished - no model found: SUCCESS!' in log)
            result['results'].append(row);dump(stage/'results.json',result);print(width,name,row['passed'],proof,flush=True)
    result['complete']=len(result['results'])==10*len(args.widths) and all(r['passed'] for r in result['results'])
    dump(stage/'results.json',result)
    return 0 if result['complete'] else 1


if __name__=='__main__':
    raise SystemExit(main())

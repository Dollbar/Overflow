"""Run python3 verification/tl_prepared_partition/run_reference.py [--label reference]
[--unit-label unit_semantics] [--replace FILE]. Replays completed independent
vectors on the raw-field RTL reference at WIDTH8/16. Outputs snapshots, traces
and logs under build/verification/tl_prepared_equivalence/LABEL. Next full miter.
"""
from pathlib import Path
import argparse
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump, execute, need, sha

REFERENCE = '1e26fbd486ca4ee96de4635fd9a2442801bfc89d'
DEPENDENCIES = ('tl_control_partition.v','tl_credit_admission.v','tl_control_decode.v','tl_control_tenure.v')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label',default='reference')
    parser.add_argument('--unit-label',default='unit_semantics')
    parser.add_argument('--replace',type=Path)
    args=parser.parse_args()
    for label in (args.label,args.unit_label): need(label.replace('_','').replace('-','').isalnum(),'invalid label')
    stage=ROOT/'build/verification/tl_prepared_equivalence'/args.label
    stage.mkdir(parents=True,exist_ok=False)
    unit=ROOT/'build/verification/tl_prepared_partition'/args.unit_label
    healthy=json.loads((unit/'results.json').read_text());need(healthy['complete'],'completed independent vectors required')
    reference=(args.replace or Path(__file__).with_name('reference.v')).resolve()
    need(reference.is_file(),'raw-field reference RTL missing')
    (stage/'reference.v').write_bytes(reference.read_bytes())
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    sources=[stage/'reference.v']
    for name in DEPENDENCIES:
        p=stage/name;p.write_bytes(subprocess.check_output(['git','show',REFERENCE+':rtl/tl/'+name],cwd=ROOT));sources.append(p)
    result=dict(complete=False,reference=REFERENCE,reference_sha256=sha(reference),oracle_sha256=sha(unit/'results.json'),sources={p.name:sha(p) for p in sources},results=[])
    for width in (8,16):
        folder=stage/f'w{width}';folder.mkdir();fixture=unit/f'w{width}'
        for name in ('vectors.hex','expected.hex'):(folder/name).write_bytes((fixture/name).read_bytes())
        tb=(fixture/'tb.sv').read_text().replace('tl_prepared_partition #','tl_prepared_reference #').replace(str(fixture),str(folder))
        (folder/'tb.sv').write_text(tb)
        compile_result=execute(['iverilog','-g2012','-s','tb','-o',str(folder/'sim.vvp'),*map(str,sources),str(folder/'tb.sv')],folder/'compile.log',120)
        row=dict(width=width,compile=compile_result,passed=False)
        if compile_result['exit']==0:
            run=execute(['vvp',str(folder/'sim.vvp')],folder/'run.log',180)
            row.update(run=run,passed=run['exit']==0 and 'PASS prepared' in (folder/'run.log').read_text())
        result['results'].append(row);dump(stage/'results.json',result);print(width,row['passed'],flush=True)
    result['complete']=all(r['passed'] for r in result['results'])
    dump(stage/'results.json',result)
    return 0 if result['complete'] else 1


if __name__=='__main__':
    raise SystemExit(main())

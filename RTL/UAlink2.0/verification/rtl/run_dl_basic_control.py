"""Run complete Basic native output checks on actual RTL clock edges.
Run: python3 verification/rtl/run_dl_basic_control.py --period-ps 640 --seed 17
Outputs: fresh build/dl_basic_control_*/ sources, vectors, compile/simulation logs and summary.
Next: audit real RTL faults, full-state induction, library mapping and original-budget STA.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

SOURCES=('rtl/dl/dl_basic_message_control.v','verification/rtl/dl_basic_control_tb.v',
         'verification/rtl/dl_basic_control_vectors.py','verification/rtl/run_dl_basic_control.py',
         'model/ualink/dl_basic_control.py','model/ualink/dl_basic_message.py',
         'model/__init__.py','model/ualink/__init__.py','config/dl_basic_control_contract.json')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--period-ps',type=int,default=640);parser.add_argument('--seed',type=int,default=17)
    parser.add_argument('--cycles',type=int,default=4000);parser.add_argument('--verilator',default='verilator')
    a=parser.parse_args()
    if not 4<=a.period_ps<=1_000_000_000 or a.cycles<1:parser.error('TB period4..1e9ps and positive cycles required')
    root=Path(__file__).resolve().parents[2];hashes={n:sha(root/n) for n in SOURCES}
    run=Path(tempfile.mkdtemp(prefix='dl_basic_control_',dir=root/'build'));snapshot=run/'snapshot'
    for n in SOURCES:
        (snapshot/n).parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/n,snapshot/n)
    result=dict(directory=str(run.relative_to(root)),period_ps=a.period_ps,seed=a.seed,random_cycles=a.cycles,
                source_sha256=hashes,stages=[],passed=False,full_actual_clock=True)
    start=time.monotonic()
    def unchanged():return all(sha(root/n)==sha(snapshot/n)==h for n,h in hashes.items())
    def invoke(command,name,timeout=180):
        assert unchanged(),'source changed'
        with (run/name).open('w') as stream:
            try:status=subprocess.run(command,cwd=snapshot,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout).returncode
            except subprocess.TimeoutExpired:status=124
        result['stages'].append(dict(command=list(map(str,command)),log=name,exit_status=status,sha256=sha(run/name)))
        assert status==0,(name,status)
    try:
        result['verilator']=subprocess.check_output([a.verilator,'--version'],text=True,timeout=20).strip()
        invoke([sys.executable,'verification/rtl/dl_basic_control_vectors.py','--output',str(run/'vectors.mem'),'--summary',str(run/'vectors.json'),
                '--period-ps',str(a.period_ps),'--seed',str(a.seed),'--cycles',str(a.cycles)],'vectors.log')
        expected=json.loads((run/'vectors.json').read_text());result.update(expected=expected,vectors_sha256=sha(run/'vectors.mem'),vectors_summary_sha256=sha(run/'vectors.json'))
        invoke([a.verilator,'--binary','--timing','--language','1364-2001','-Wall','--top-module','dl_basic_control_tb',
                '--Mdir',str(run/'obj'),f'-GC_CLOCK_PERIOD_PS={a.period_ps}','rtl/dl/dl_basic_message_control.v','verification/rtl/dl_basic_control_tb.v'],'compile.log')
        invoke([str(run/'obj/Vdl_basic_control_tb'),f'+VECTORS={run}/vectors.mem'],'sim.log')
        text=(run/'sim.log').read_text();matches=re.findall(r'^PASS dl_basic_control (.+)$',text,re.M)
        assert len(matches)==1 and 'FAIL' not in text
        observed={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',matches[0])}
        assert observed==dict(rows=expected['rows'],**expected['events'])
        assert expected['input_bits']==103 and expected['output_bits']==194 and expected['full_actual_clock']
        assert unchanged()
        result.update(observed=observed,source_unchanged=True,passed=True)
    except (AssertionError,OSError,ValueError,subprocess.SubprocessError) as error:
        result['failure']=str(error)
    result['elapsed_seconds']=time.monotonic()-start
    (run/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(dict(directory=result['directory'],passed=result['passed'],failure=result.get('failure'))),flush=True)
    return 0 if result['passed'] else 1


if __name__=='__main__':raise SystemExit(main())

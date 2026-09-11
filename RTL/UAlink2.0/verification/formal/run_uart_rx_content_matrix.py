"""Prove all 32 data planes of the actual SRAM-backed UART RX path.

Run: python3 verification/formal/run_uart_rx_content_matrix.py --kd28-root /authorized/models --depth 128 --jobs 3
Outputs: fresh build/uart_rx_content_matrix_*/matrix.json, immutable source snapshot,
rotation theorem log and 32 actual-memory reset/induction proof directories.
Next: audit failures and actual RTL fault controls; this is content/order safety,
not a complete UART lifecycle or physical implementation signoff.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor,as_completed
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from verification.formal.run_uart_rx_content_proof import DEPS,NAMES,run_proof,sha


def planes_complete(cases,depth):
    """Require all 32 distinct bits, identical inputs and every declared proof gate."""
    if type(depth) is not int or not 1<=depth<=4095 or len(cases)!=32:return False
    if not all(isinstance(c,dict) for c in cases):return False
    bits=[c.get('proof_bit') for c in cases]
    if any(type(bit) is not int for bit in bits) or set(bits)!=set(range(32)):return False
    source=cases[0].get('source_sha256');models=cases[0].get('dependency_sha256')
    if not isinstance(source,dict) or not source or not isinstance(models,dict) or not models:return False
    return all(type(c.get('depth')) is int and c['depth']==depth and
               type(c.get('exit_status')) is int and c['exit_status']==0 and
               type(c.get('compared_output_bits')) is int and c['compared_output_bits']==93 and
               all(c.get(key) is True for key in
                   ('passed','content','reset_proved','induction_proved','source_unchanged')) and
               c.get('source_sha256')==source and c.get('dependency_sha256')==models
               for c in cases)


def run_matrix(root,dep,depth=128,jobs=3,yosys='yosys'):
    root=Path(root).resolve(strict=True);dep=Path(dep).resolve(strict=True)
    if type(depth) is not int or not 1<=depth<=4095:raise ValueError('depth must be 1..4095')
    if type(jobs) is not int or not 1<=jobs<=4:raise ValueError('jobs must be 1..4')
    (root/'build').mkdir(exist_ok=True)
    run=Path(tempfile.mkdtemp(prefix='uart_rx_content_matrix_',dir=root/'build'))
    snapshot=run/'snapshot';hashes={n:sha(root/n) for n in NAMES};deps={n:sha(dep/n) for n in DEPS}
    for name in NAMES:
        target=snapshot/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/name,target)
    def unchanged():
        assert all(sha(root/n)==sha(snapshot/n)==h for n,h in hashes.items()),'project input changed'
        assert all(sha(dep/n)==h for n,h in deps.items()),'actual SRAM model changed'
    record=dict(directory=str(run.relative_to(root)),depth=depth,data_bits=32,workers=jobs,
                source_sha256=hashes,dependency_root=str(dep),dependency_sha256=deps,
                planes=[],passed=False,complete_word_content_proved=False)
    def save():(run/'matrix.json').write_text(json.dumps(record,indent=2)+'\n')
    save();unchanged()
    if depth==128:
        command=[yosys,'-Q','-T','-c','scripts/prove_receive_rotation.tcl']
        with (run/'rotation.log').open('w') as log:
            try:status=subprocess.run(command,cwd=snapshot,stdout=log,stderr=subprocess.STDOUT,timeout=60).returncode
            except subprocess.TimeoutExpired:status=124
        text=(run/'rotation.log').read_text()
        theorem=dict(command=command,exit_status=status,log_sha256=sha(run/'rotation.log'),
                     passed=status==0 and 'RECEIVE_ROTATION_BOUND_PROVED depth=128\n' in text and
                     text.count('SAT proof finished - no model found: SUCCESS!')==1 and
                     'Warning:' not in text and 'ERROR:' not in text)
        record['rotation_theorem']=theorem;save()
        if not theorem['passed']:unchanged();return record
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        futures={pool.submit(run_proof,snapshot,dep,depth,True,yosys,bit):bit for bit in range(32)}
        for future in as_completed(futures):
            bit=futures[future]
            try:case=future.result()
            except Exception as error:case=dict(proof_bit=bit,passed=False,error=repr(error))
            record['planes'].append(case);record['planes'].sort(key=lambda c:c['proof_bit']);save()
            print(f"bit {bit}: {'PASS' if case['passed'] else 'FAIL'}",flush=True)
    unchanged();record['source_unchanged']=True
    record['passed']=planes_complete(record['planes'],depth) and all(
        c['source_sha256']==hashes and c['dependency_sha256']==deps for c in record['planes'])
    record['complete_word_content_proved']=record['passed'];save();return record


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--depth',type=int,default=128)
    p.add_argument('--jobs',type=int,default=3,choices=range(1,5));p.add_argument('--yosys',default='yosys')
    a=p.parse_args();record=run_matrix(ROOT,a.kd28_root,a.depth,a.jobs,a.yosys)
    print(json.dumps(record),flush=True);return 0 if record['passed'] else 1


if __name__=='__main__':raise SystemExit(main())

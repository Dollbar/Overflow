"""Snapshot and prove the actual RX path with arbitrary native inputs.

Run: python3 verification/formal/run_uart_rx_proof.py --kd28-root /authorized/models --depth 3 --content
Outputs: fresh build/uart_rx_proof_*/snapshot, actual-memory observations, proof log/JSON.
Next: audit all assertions and real fault controls before claiming the stated scope.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[2]
NAMES=('rtl/dl/dl_uart_rx_path.v','rtl/upli/upli_receive_fifo.v','rtl/upli/upli_receive_storage.v',
       'verification/formal/uart_rx_properties.v','verification/formal/upli_receive_word_invariant.v',
       'verification/formal/run_uart_rx_proof.py','scripts/prove_uart_rx.tcl','config/uart_rx_path_contract.json')
DEPS=('Library/models/kd28/sram/rtl/kd28_sram_sdp_model.v','Library/models/kd28/sram/rtl/kd28_sram_cells.v',
      'Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v')

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def run_proof(root,dep,depth,content,yosys='yosys'):
    root=Path(root).resolve(strict=True);dep=Path(dep).resolve(strict=True)
    if type(depth) is not int or not 1<=depth<=4095:raise ValueError('depth must be1..4095')
    run=Path(tempfile.mkdtemp(prefix='uart_rx_proof_',dir=root/'build'))
    snapshot=run/'snapshot'
    hashes={n:sha(root/n) for n in NAMES};deps={n:sha(dep/n) for n in DEPS}
    for name in NAMES:
        target=snapshot/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/name,target)
    def unchanged():
        assert all(sha(root/n)==sha(snapshot/n)==h for n,h in hashes.items()),'project input changed'
        assert all(sha(dep/n)==h for n,h in deps.items()),'actual SRAM model changed'
    env=os.environ.copy();env.update(UALINK_DEPTH=str(depth),UALINK_CONTENT=str(int(content)),
       UALINK_KD28_ROOT=str(dep),UALINK_BUILD_DIR=str(run/'proof'))
    command=[yosys,'-Q','-T','-c','scripts/prove_uart_rx.tcl']
    record=dict(directory=str(run.relative_to(root)),depth=depth,content=bool(content),
       source_sha256=hashes,dependency_root=str(dep),dependency_sha256=deps,
       version=subprocess.check_output([yosys,'-V'],text=True,timeout=20).strip(),command=command,passed=False)
    start=time.monotonic();unchanged()
    with (run/'proof.log').open('w') as log:
        try:r=subprocess.run(command,cwd=snapshot,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=360).returncode
        except subprocess.TimeoutExpired:r=124
    unchanged();text=(run/'proof.log').read_text()
    record.update(exit_status=r,log_sha256=sha(run/'proof.log'),elapsed_seconds=time.monotonic()-start,
       reset_proved='UART_RX_RESET_BASE_PROVED\n' in text,
       induction_proved='UART_RX_FULL_INDUCTION_PROVED\n' in text,
       source_unchanged=True,artifact_sha256={str(p.relative_to(run)):sha(p) for p in (run/'proof').glob('*') if p.is_file()})
    record['passed']=(r==0 and record['reset_proved'] and record['induction_proved'] and
       text.count('SAT proof finished - no model found: SUCCESS!')==2 and
       f'UART_RX_FUNCTIONAL_PROVED depth={depth} content={int(content)} outputs=22 output_bits=124 control_state_bits=20\n' in text and
       not re.search(r'^\s*(Warning:|ERROR:)',text,re.M))
    (run/'summary.json').write_text(json.dumps(record,indent=2)+'\n')
    return record

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True)
    p.add_argument('--depth',type=int,default=128);p.add_argument('--content',action='store_true');p.add_argument('--yosys',default='yosys')
    a=p.parse_args();record=run_proof(ROOT,a.kd28_root,a.depth,a.content,a.yosys)
    print(json.dumps(record),flush=True);return 0 if record['passed'] else 1

if __name__=='__main__':raise SystemExit(main())

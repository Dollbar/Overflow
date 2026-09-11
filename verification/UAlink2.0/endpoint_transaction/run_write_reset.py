#!/usr/bin/env python3
"""Verify actual mixed Write network reset with retained backend memory.
Run: python3 verification/endpoint_transaction/run_write_reset.py --label NEW --kd28-root PATH [--bank-depth 1]
Outputs per-window fixtures, source snapshots, compile/run logs and result.json under build/verification/endpoint_transaction/NEW.
Next inspect cancellation versus retained side effects; this is not independent LinkDown recovery.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
COUNT=9

def fixtures(folder,reset_stage):
    descriptors=[];payloads=[];masks=[];expect_masks=[];reads=[];retained=[]
    old_blobs=[bytes((side*67+byte*13+0x31)&255 for byte in range(256)) for side in range(2)]
    old_mask=sum(1<<byte for byte in range(256) if byte%3!=1)
    prior=[bytes(old_blobs[side][byte] if (reset_stage==3 and (old_mask>>byte)&1) else 0 for byte in range(256)) for side in range(2)]
    for epoch in range(2):
        for side in range(2):
            memory=bytearray(prior[side]) if epoch else bytearray(256)
            for index in range(COUNT):
                kind=(index==0) if epoch==0 else (index==4)
                full=bool(epoch and kind)
                tag=1024 if kind else 1040+index
                address=0 if kind else ((index if index<4 else index-5)*64 if epoch else 0)
                size=256 if kind else 64
                blob=old_blobs[side] if epoch==0 else bytes(value^0xd5 for value in old_blobs[side])
                mask=((1<<256)-1 if full else old_mask) if kind else 0
                attr,asi,meta=(0x81,2,0x5a) if kind else (255,0,0)
                word=(int(kind)<<93)|(int(full)<<92)|(tag<<81)|(address<<24)|((size//4-1)<<18)|(attr<<10)|(asi<<8)|meta
                descriptors.append(f'{word:024x}');payloads.append(blob[::-1].hex());masks.append(f'{(0 if full else mask):064x}');expect_masks.append(f'{mask:064x}')
                if kind:
                    for byte in range(256):
                        if (mask>>byte)&1:memory[byte]=blob[byte]
                    reads.append('0'*128)
                else:reads.append(bytes(memory[address:address+64])[::-1].hex())
    for side in range(2):retained.append(prior[1-side][::-1].hex())
    for name,values in [('descriptors',descriptors),('payloads',payloads),('byte_enables',masks),('expected_masks',expect_masks),('expected_reads',reads),('retained_memory',retained)]:
        (folder/(name+'.hex')).write_text('\n'.join(values)+'\n')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--kd28-root',required=True,type=Path)
    p.add_argument('--stage',type=int,choices=(1,2,3));p.add_argument('--bank-depth',type=int,choices=(1,3),default=3)
    p.add_argument('--fault',choices=('endpoint_reset','backend_cancel'));a=p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
    if a.fault and a.stage is None:p.error('fault requires explicit --stage')
    out=ROOT/'build/verification/endpoint_transaction'/a.label;out.mkdir(parents=True,exist_ok=False)
    manifest=ROOT/'third_party/kd28_dependency.json';manifest_bytes=manifest.read_bytes();deps=json.loads(manifest_bytes);cached={}
    for relative,expected in deps['functional_sources_sha256'].items():
        path=a.kd28_root.resolve()/relative;blob=path.read_bytes()
        if hashlib.sha256(blob).hexdigest()!=expected:raise ValueError('dependency hash mismatch: '+relative)
        cached[path]=blob
    tb=ROOT/'verification/endpoint_transaction/write_reset_tb.sv';sources=sorted((ROOT/'rtl').rglob('*.v'))+list(cached)+[tb]
    copies=[];hashes={};mapping={}
    for index,source in enumerate(sources):
        dest=out/'sources'/(str(index)+'_'+source.name);dest.parent.mkdir(exist_ok=True)
        blob=cached[source] if source in cached else source.read_bytes();dest.write_bytes(blob);copies.append(dest)
        hashes[str(source)]=hashlib.sha256(blob).hexdigest();mapping[str(source)]=str(dest.relative_to(out))
    for source,name,blob in [(Path(__file__),'runner.py',Path(__file__).read_bytes()),(manifest,'dependency.json',manifest_bytes)]:
        (out/name).write_bytes(blob);hashes[str(source)]=hashlib.sha256(blob).hexdigest();mapping[str(source)]=name
    result={'passed':False,'bank_depth':a.bank_depth,'fault':a.fault,'scope':'uniform synchronous network reset; memory retained, pending/results cancelled; no independent LinkDown','sources':hashes,'snapshot_sources':mapping,'cases':[]}
    for window in ([a.stage] if a.stage else [1,2,3]):
        folder=out/f'stage_{window}';folder.mkdir();fixtures(folder,window)
        command=['iverilog','-g2012','-s','tb',f'-Ptb.RESET_STAGE={window}',f'-Ptb.BANK_DEPTH={a.bank_depth}',f'-Ptb.FAULT={ {None:0,"endpoint_reset":1,"backend_cancel":2}[a.fault]}','-o',str(folder/'sim.vvp'),*map(str,copies)]
        case={'stage':window}
        for phase,cmd in [('compile',command),('run',['vvp',str(folder/'sim.vvp')])]:
            case[phase+'_command']=cmd
            with (folder/(phase+'.log')).open('w') as log:
                try:code=subprocess.run(cmd,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=180).returncode
                except subprocess.TimeoutExpired:code=124
            case[phase+'_exit']=code
            if phase=='compile' and code:break
        log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
        marker={'endpoint_reset':'WRITE_RESET_STATE','backend_cancel':'WRITE_RESET_OLD_BACKEND'}.get(a.fault,'WRITE_RESET_PASS')
        case['passed']=case.get('compile_exit')==0 and case.get('run_exit')==(1 if a.fault else 0) and marker in log and 'WRITE_RESET_TARGET' in log
        result['cases'].append(case);print(json.dumps({k:v for k,v in case.items() if k in ('stage','compile_exit','run_exit','passed')}),flush=True)
    result['passed']=all(case['passed'] for case in result['cases']);result['artifacts_sha256']={str(f.relative_to(out)):hashlib.sha256(f.read_bytes()).hexdigest() for f in out.rglob('*') if f.is_file()}
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

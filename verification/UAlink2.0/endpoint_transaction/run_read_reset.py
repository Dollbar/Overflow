#!/usr/bin/env python3
"""Verify actual full Read network reset with retained backend memory.
Run: python3 verification/endpoint_transaction/run_read_reset.py --label NEW --kd28-root PATH [--bank-depth 1] [--stage 2 --partial-beats 1|2|3]
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
COUNT=4

def fixtures(folder):
    descriptors=[];payloads=[];bes=[];memory_masks=[];masks=[];expected=[];raw=[];statuses=[];beats=[];retained=[]
    blobs=[bytes(1+((side*73+byte*11)%255) for byte in range(256)) for side in range(2)]
    for epoch in range(2):
        for side in range(2):
            memory=bytearray(blobs[side]) if epoch else bytearray(256)
            program=[(True,1536,0,256,0x81,0),(False,1024,0,256,0xff,0),(False,1,0,4,0,0),(False,2,0,4,0,0)] if not epoch else [(False,1024,0,256,0x5a,0),(False,1792,60,8,0xa5,0),(False,31,124,4,0,0),(False,2047,0,256,0xff,3)]
            assert len(program)==COUNT
            for index,(kind,tag,address,size,attr,status) in enumerate(program):
                asi,metadata=(2,0x5a) if kind else ((index+side)%4,(0x33+index+17*epoch)&255)
                region=0
                for byte in range(address,address+size):
                    dword=(byte-address)//4;lane=(byte-address)%4
                    enable=kind or ((attr>>lane)&1 if dword==0 else ((attr>>(lane+4))&1 if dword==size//4-1 else 1))
                    if enable:region|=1<<byte
                num=((address%64)+size+63)//64
                actual=bytearray([0xd7]*256);masked=bytearray(256);mask=0 if kind or status else region>>(64*(address//64))
                if kind:memory[:]=blobs[side];actual=bytearray(256)
                else:
                    for byte in range(num*64):actual[byte]=memory[(address//64)*64+byte]
                    for byte in range(256):
                        if (mask>>byte)&1:masked[byte]=actual[byte]
                word=(int(kind)<<93)|(int(kind)<<92)|(tag<<81)|(address<<24)|((size//4-1)<<18)|(attr<<10)|(asi<<8)|metadata
                descriptors.append(f'{word:024x}');payloads.append(blobs[side][::-1].hex());bes.append('0'*64);memory_masks.append(f'{region:064x}');masks.append(f'{mask:064x}');expected.append(masked[::-1].hex());raw.append(actual[::-1].hex());statuses.append(f'{status:x}');beats.append(f'{num:x}')
    retained=[blobs[1-side][::-1].hex() for side in range(2)]
    for name,values in [('descriptors',descriptors),('payloads',payloads),('byte_enables',bes),('memory_masks',memory_masks),('expected_masks',masks),('expected_data',expected),('expected_raw',raw),('statuses',statuses),('num_beats',beats),('retained_memory',retained)]:
        (folder/(name+'.hex')).write_text('\n'.join(values)+'\n')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--kd28-root',required=True,type=Path)
    p.add_argument('--partial-beats',type=int,choices=(1,2,3),default=1)
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
    tb=ROOT/'verification/endpoint_transaction/read_reset_tb.sv';sources=sorted((ROOT/'rtl').rglob('*.v'))+list(cached)+[tb]
    copies=[];hashes={};mapping={}
    for index,source in enumerate(sources):
        dest=out/'sources'/(str(index)+'_'+source.name);dest.parent.mkdir(exist_ok=True)
        blob=cached[source] if source in cached else source.read_bytes();dest.write_bytes(blob);copies.append(dest)
        hashes[str(source)]=hashlib.sha256(blob).hexdigest();mapping[str(source)]=str(dest.relative_to(out))
    for source,name,blob in [(Path(__file__),'runner.py',Path(__file__).read_bytes()),(manifest,'dependency.json',manifest_bytes)]:
        (out/name).write_bytes(blob);hashes[str(source)]=hashlib.sha256(blob).hexdigest();mapping[str(source)]=name
    result={'passed':False,'bank_depth':a.bank_depth,'fault':a.fault,'partial_beats':a.partial_beats,'scope':'uniform synchronous network reset; memory retained, pending/results cancelled; no independent LinkDown','sources':hashes,'snapshot_sources':mapping,'cases':[]}
    for window in ([a.stage] if a.stage else [1,2,3]):
        folder=out/f'stage_{window}';folder.mkdir();fixtures(folder)
        command=['iverilog','-g2012','-s','tb',f'-Ptb.RESET_STAGE={window}',f'-Ptb.BANK_DEPTH={a.bank_depth}',f'-Ptb.PARTIAL_BEATS={a.partial_beats}',f'-Ptb.FAULT={ {None:0,"endpoint_reset":1,"backend_cancel":2}[a.fault]}','-o',str(folder/'sim.vvp'),*map(str,copies)]
        case={'stage':window,'partial_beats':a.partial_beats if window==2 else None}
        for phase,cmd in [('compile',command),('run',['vvp',str(folder/'sim.vvp')])]:
            case[phase+'_command']=cmd
            with (folder/(phase+'.log')).open('w') as log:
                try:code=subprocess.run(cmd,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=180).returncode
                except subprocess.TimeoutExpired:code=124
            case[phase+'_exit']=code
            if phase=='compile' and code:break
        log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
        marker={'endpoint_reset':'READ_RESET_STATE','backend_cancel':'READ_RESET_OLD_BACKEND'}.get(a.fault,'READ_RESET_PASS')
        case['passed']=case.get('compile_exit')==0 and case.get('run_exit')==(1 if a.fault else 0) and marker in log and 'READ_RESET_TARGET' in log
        result['cases'].append(case);print(json.dumps({k:v for k,v in case.items() if k in ('stage','partial_beats','compile_exit','run_exit','passed')}),flush=True)
    result['passed']=all(case['passed'] for case in result['cases']);result['artifacts_sha256']={str(f.relative_to(out)):hashlib.sha256(f.read_bytes()).hexdigest() for f in out.rglob('*') if f.is_file()}
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

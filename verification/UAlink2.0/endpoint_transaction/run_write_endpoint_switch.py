#!/usr/bin/env python3
"""Run actual bidirectional Endpoint/Switch Write-then-Read memory transactions.
Run: python3 verification/endpoint_transaction/run_write_endpoint_switch.py --label NEW --kd28-root PATH [--all-lengths] [--inject] [--bank-depth 1]
Outputs independent byte fixtures, source snapshots, compile/run logs and result.json under build/verification/endpoint_transaction/NEW.
Next inspect every actual write execution and read completion before claiming a wider protocol profile.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())

def make_program(all_lengths):
    program=[]
    def write(address,size,full=False,zero=False):program.append(dict(write=True,full=full,address=address,size=size,zero=zero))
    def read(address):program.append(dict(write=False,full=False,address=address,size=64,zero=False))
    write(0,256,True)
    for address in range(0,256,64):read(address)
    write(60,8);read(0);read(64)
    write(128,64,zero=True);read(128)
    if all_lengths:
        for dwords in range(1,65):
            address=4*((dwords*13)%(65-dwords));size=dwords*4
            write(address,size)
            for beat in range(address//64,(address+size-1)//64+1):read(beat*64)
        for start in range(4):
            for beats in range(1,5-start):
                write(start*64,beats*64,True)
                for beat in range(start,start+beats):read(beat*64)
    return program

def fixtures(stage,program):
    desc=[];payload=[];bes=[];expected=[];memory_commands=[]
    for side in range(2):
        # This reference consumes application bytes, not received RTL fields or BFM storage.
        memory=bytearray(256)
        for index,op in enumerate(program):
            address,size=op['address'],op['size'];kind=op['write'];full=op['full']
            blob=bytes(((side+1)*53+index*19+byte*7+(byte//64)*31)&255 for byte in range(256))
            enabled=[byte for byte in range(address,address+size) if full or (not op['zero'] and (byte+index+side)%3!=0)] if kind else []
            mask=sum(1<<byte for byte in enabled)
            attr=(0x81^index)&255 if kind else 255;asi=(index+side)%4 if kind else 0;meta=(0x5a+index)&255 if kind else 0
            word=(int(kind)<<93)|(int(full)<<92)|((1024+index)<<81)|(address<<24)|((size//4-1)<<18)|(attr<<10)|(asi<<8)|meta
            desc.append(f'{word:024x}');payload.append(blob[::-1].hex());bes.append(f'{(mask if not full else ((1<<256)-1)^mask):064x}')
            memory_commands.append(f'{mask:064x}')
            if kind:
                base=(address//64)*64
                for byte in enabled:memory[byte]=blob[byte-base]
                expected.append('0'*128)
            else:expected.append(bytes(memory[address:address+64])[::-1].hex())
    for name,values in [('descriptors',desc),('payloads',payload),('byte_enables',bes),('expected_masks',memory_commands),('expected_reads',expected)]:
        (stage/(name+'.hex')).write_text('\n'.join(values)+'\n')
    (stage/'program.json').write_text(json.dumps(program,indent=2)+'\n')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--kd28-root',required=True,type=Path)
    p.add_argument('--all-lengths',action='store_true');p.add_argument('--inject',action='store_true');p.add_argument('--bank-depth',type=int,choices=(1,3),default=3)
    p.add_argument('--fault',choices=['drop_write_be','early_write_result'])
    a=p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
    stage=ROOT/'build/verification/endpoint_transaction'/a.label;stage.mkdir(parents=True,exist_ok=False)
    manifest=ROOT/'third_party/kd28_dependency.json';manifest_bytes=manifest.read_bytes();dep=json.loads(manifest_bytes);dependencies=[]
    for relative,h in dep['functional_sources_sha256'].items():
        path=a.kd28_root.resolve()/relative
        if hashlib.sha256(path.read_bytes()).hexdigest()!=h:raise ValueError('dependency hash mismatch: '+relative)
        dependencies.append(path)
    sources=sorted((ROOT/'rtl').rglob('*.v'))+dependencies
    tb=ROOT/'verification/endpoint_transaction/write_endpoint_switch_tb.sv'
    sources.append(tb);copies=[];source_hashes={}
    for index,source in enumerate(sources):
        dest=stage/'sources'/(str(index)+'_'+source.name);dest.parent.mkdir(exist_ok=True);blob=source.read_bytes();dest.write_bytes(blob);copies.append(dest);source_hashes[str(source)]=hashlib.sha256(blob).hexdigest()
    runner_bytes=Path(__file__).read_bytes();(stage/'runner.py').write_bytes(runner_bytes);(stage/'dependency.json').write_bytes(manifest_bytes)
    source_hashes[str(Path(__file__))]=hashlib.sha256(runner_bytes).hexdigest();source_hashes[str(manifest)]=hashlib.sha256(manifest_bytes).hexdigest()
    program=make_program(a.all_lengths);fixtures(stage,program)
    command=['iverilog','-g2012','-s','tb',f'-Ptb.COUNT={len(program)}',f'-Ptb.INJECT={int(a.inject)}',f'-Ptb.BANK_DEPTH={a.bank_depth}',f'-Ptb.FAULT={ {None:0,"drop_write_be":1,"early_write_result":2}[a.fault]}','-o',str(stage/'sim.vvp'),*map(str,copies)]
    result={'passed':False,'requests_per_side':len(program),'writes_per_side':sum(op['write'] for op in program),'all_lengths':a.all_lengths,'inject':a.inject,'bank_depth':a.bank_depth,'fault':a.fault,'sources':source_hashes,'snapshot_sources':{str(src):str(dst.relative_to(stage)) for src,dst in zip(sources,copies)}}
    result['snapshot_sources'].update({str(Path(__file__)):'runner.py',str(manifest):'dependency.json'})
    for phase,cmd in [('compile',command),('run',['vvp',str(stage/'sim.vvp')])]:
        result[phase+'_command']=cmd
        with (stage/(phase+'.log')).open('w') as log:
            try:code=subprocess.run(cmd,cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=240).returncode
            except subprocess.TimeoutExpired:code=124
        result[phase+'_exit']=code
        if phase=='compile' and code:break
    log=(stage/'run.log').read_text() if (stage/'run.log').exists() else ''
    if a.fault:
        marker={'drop_write_be':'WRITE_ESE_READ_DATA','early_write_result':'WRITE_ESE_EXECUTION_CAUSALITY'}[a.fault]
        result['passed']=result.get('compile_exit')==0 and result.get('run_exit')==1 and marker in log
    else:result['passed']=result.get('compile_exit')==0 and result.get('run_exit')==0 and 'WRITE_ESE_PASS' in log
    result['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
    (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k in ['passed','compile_exit','run_exit','requests_per_side','writes_per_side']}));return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

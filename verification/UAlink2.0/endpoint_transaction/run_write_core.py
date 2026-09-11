#!/usr/bin/env python3
"""Exercise two real mixed transaction cores through a modeled prepared-record bridge.

Run: python3 verification/endpoint_transaction/run_write_core.py --label NEW
Outputs: build/verification/endpoint_transaction/NEW/{result.json,rtl,tb.sv,*.log}.
Next: repeat these byte/identity checks through actual prepared TL, Switch and DL.
This is core RTL simulation, not an Endpoint/Switch or credit/framing regression.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import time

ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())


def vectors(stage):
    operations=[(1,1,0,63,0),(0,0,0,15,0),(0,0,64,15,0),(1,0,60,17,0),
                (0,0,0,15,0),(0,0,64,15,0),(0,0,128,15,0),(1,0,128,31,0),
                (0,0,128,15,0),(1,1,192,15,0),(0,0,192,15,0),(1,0,252,0,0),
                (0,0,192,15,0),(1,0,0,15,2),(1,0,0,15,6),(1,0,0,15,8),
                (1,1,1<<56,15,3),(0,0,0,15,0),(0,0,1<<56,15,3)]
    memories=[bytearray((i*17+(i>>4)*23+side*91+9)&255 for i in range(4096)) for side in range(2)]
    rows=[]
    for side in range(2):
        (stage/f"initial{side}.hex").write_text(''.join(f'{v:02x}\n' for v in memories[side]))
    for side in range(2):
        memory=memories[1-side]
        for index,(write,full,address,length,status) in enumerate(operations):
            size=4*(length+1);n=((address%64)+size+63)//64
            data=int.from_bytes(bytes((side*67+index*31+j*7+(j>>6)*41)&255 for j in range(n*64)),'little') if write else 0
            span=((1<<size)-1)<<(address%256)
            be=span if full else span&int('a5'*32,16)
            if index==7:be=0
            if index==11:be=1<<255
            be&=(1<<256)-1
            attr=(index*13+side+17)&255 if write else 255
            asi=(index+side)%4 if write else 0
            meta=(index*29+side+1)&255 if write else 0
            tag=(1024+index*53+side*311)&2047
            if write and status==0:
                for b in range(256):
                    if be>>b&1:memory[(address&~255)+b]=data>>(8*(b-(address%256//64)*64))&255
            expected=0 if write or status else int.from_bytes(memory[address:address+64],'little')
            input_be=0 if full else be  # Full must rebuild its mask even when the application supplies zero.
            values=[write,full,tag,address,length,attr,asi,meta,data,input_be,be,status,expected]
            rows.append(' '.join(f'{v:x}' for v in values)+'\n')
    (stage/'vectors.txt').write_text(''.join(rows))
    for side in range(2):(stage/f'final{side}.hex').write_text(''.join(f'{v:02x}\n' for v in memories[side]))
    return len(operations)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--label',required=True);p.add_argument('--capacity',type=int,choices=(1,2,3,4),default=4)
    p.add_argument('--baseline-source',type=Path,help='retain old-core interface red evidence; compile failure remains failure')
    p.add_argument('--fault',choices=('write_be','write_data','dispatch'))
    a=p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',a.label):p.error('safe new label required')
    stage=ROOT/'build/verification/endpoint_transaction'/a.label;stage.mkdir(parents=True,exist_ok=False)
    (stage/'rtl').mkdir();shutil.copyfile(__file__,stage/'runner.py')
    sources=sorted((ROOT/'rtl/endpoint').glob('*.v'))+[ROOT/'rtl/tl/tl_control_decode.v']
    copies=[];hashes={};mutated=False
    for source in sources:
        data=(a.baseline_source if a.baseline_source and source.name=='endpoint_transaction_core.v' else source).read_bytes()
        hashes[str(source)]=hashlib.sha256(data).hexdigest();target=stage/'rtl'/source.name
        if a.fault and source.name=='endpoint_transaction_core.v':
            before,after={
                'write_be':('.o_mem_data(o_write_mem_data),.o_mem_be(o_write_mem_be)', '.o_mem_data(o_write_mem_data),.o_mem_be()'),
                'write_data':('.i_request_data(request_data),.i_request_be(request_be)', '.i_request_data(2048\'d0),.i_request_be(request_be)'),
                'dispatch':('assign dispatch_allowed=!dispatch_busy;','assign dispatch_allowed=1\'b1;'),
            }[a.fault]
            text=data.decode()
            if text.count(before)!=1:raise ValueError('fault anchor missing/ambiguous')
            data=text.replace(before,after).encode();mutated=True
        target.write_bytes(data);copies.append(target)
    if a.fault and not mutated:raise ValueError('fault not applied')
    num=vectors(stage)
    tb=Path(__file__).with_name('write_core_tb.sv').read_text().replace('@@COUNT@@',str(num))
    (stage/'tb.sv').write_text(tb)
    result=dict(scope='RTL_SIM two actual transaction cores, modeled prepared/receive transport; not actual ESE',capacity=a.capacity,source_sha256=hashes,fault=a.fault,baseline_source=str(a.baseline_source) if a.baseline_source else None,cases=[])
    commands=[('compile',['iverilog','-g2012','-s','tb',f'-Ptb.CAPACITY={a.capacity}','-o','sim.vvp',*map(str,copies),'tb.sv']),('run',['vvp','sim.vvp'])]
    for name,command in commands:
        start=time.monotonic()
        with (stage/(name+'.log')).open('w') as log:
            try:code=subprocess.run(command,cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=120).returncode
            except subprocess.TimeoutExpired:code=124
        result[name]=dict(command=command,returncode=code,seconds=round(time.monotonic()-start,3))
        if code and name=='compile':break
    log=(stage/'run.log').read_text() if (stage/'run.log').exists() else ''
    result['passed']=result.get('compile',{}).get('returncode')==0 and result.get('run',{}).get('returncode')==0 and 'MIXED_CORE_PASS' in log
    if a.fault:result['passed']=result.get('compile',{}).get('returncode')==0 and result.get('run',{}).get('returncode')==1 and any(x in log for x in ('MIXED_BACKEND_BE','MIXED_BACKEND_DATA','MIXED_BACKEND_REORDER','MIXED_DISPATCH_EARLY'))
    result['coverage']={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',log)}
    result['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
    (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');print('PASS' if result['passed'] else 'FAIL',stage/'result.json')
    return 0 if result['passed'] else 1


if __name__=='__main__':raise SystemExit(main())

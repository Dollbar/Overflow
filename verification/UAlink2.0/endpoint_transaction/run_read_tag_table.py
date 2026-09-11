#!/usr/bin/env python3
"""Independent full-Read Tag-table byte/ownership regression.
Run: python3 verification/endpoint_transaction/run_read_tag_table.py --label NEW [--faults]
Output: build/verification/endpoint_transaction/NEW (isolated sources, stimuli, logs, hashes).
Next: integrate the same contracts with the real receiver, completer and TL/DL path.
"""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import re
import subprocess
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())

def fixtures(path,capacity):
    rows=[];total=0
    def emit(op,a=0,b=0,c=0,d=0,e=0,f=0,g=0,m=0,value=0):rows.append(' '.join(str(int(v)) for v in (op,a,b,c,d,e,f,g))+f' {m:x} {value:x}\n')
    def reset():emit(0)
    def alloc(tag,n,mask,write=0,port=0,ready=1,error=0):emit(1,port,tag,write,n-1,ready,error,m=mask)
    def sent(tag,port=0,error=0):emit(2,port,tag,error)
    def response(tag,off=0,nb=0,last=1,status=0,data=0,error=0,write=0,port=0,dst=0x301,poison=0):emit(3,port,tag,write,off,nb,last,status|(poison<<4)|(dst<<5),error,data)
    def complete(tag,status,mask,data,write=0,port=0):
        nonlocal total
        emit(4,port,tag,write,status,int(status==0 and not write),m=mask if status==0 and not write else 0,value=data if status==0 and not write else 0);total+=1
    def beats(tag,n):return [bytes((tag*11+k*67+b*3+(b//8))&255 for b in range(64)) for k in range(n)]
    def expected(bs,mask):return int.from_bytes(bytes(v if (mask>>i)&1 else 0 for i,v in enumerate(b''.join(bs))),'little')
    # Permutations and statuses are stimulus enumeration; expected bytes use a bytewise mask.
    for n in range(1,5):
        for order in itertools.permutations(range(n)):
            for status in (0,2,3,6,8):
                tag=2047-n;bs=beats(tag,n);mask=sum(1<<i for i in range(n*64) if (i+status)%5 not in (1,3))
                reset();alloc(tag,n,mask);sent(tag)
                for index,k in enumerate(order):
                    response(tag,k,0,index==n-1,status,int.from_bytes(bs[k],'little'))
                    if index<n-1:emit(5,a=1)
                complete(tag,status,mask,expected(bs,mask));emit(5)
        for status in (0,2,3,6,8):
            reset();tag=1033+n;bs=beats(tag,n);mask=(1<<(n*64))-1;alloc(tag,n,mask);sent(tag)
            for k in range(n):response(tag,k,n-1,k==n-1,status,int.from_bytes(bs[k],'little'))
            # Ownership still excludes the same Tag after complete data and before application retirement.
            alloc(tag,1,0,write=1,ready=0,error=1)
            complete(tag,status,mask,expected(bs,mask))
    # Each malformed transfer must be diagnosed without completing or corrupting collected bytes.
    for bad in ('early_last','missing_last','duplicate','offset','status','mode','multi_order','multi_length','kind','dst','tag','poison','reserved'):
        reset();tag=1555;bs=beats(tag,2);mask=(1<<128)-1;alloc(tag,2,mask);sent(tag)
        response(tag,0,0,0,0,int.from_bytes(bs[0],'little'))
        args=dict(tag=tag,off=1,last=1,data=int.from_bytes(bs[1],'little'),error=1)
        if bad=='early_last':args.update(off=0)
        elif bad=='missing_last':args.update(last=0)
        elif bad=='duplicate':args.update(off=0,last=0)
        elif bad=='offset':args.update(off=3)
        elif bad=='status':args.update(status=2)
        elif bad=='mode':args.update(nb=1)
        elif bad=='multi_order':args.update(nb=1,off=0)
        elif bad=='multi_length':args.update(nb=2)
        elif bad=='kind':args.update(write=1)
        elif bad=='dst':args.update(dst=0x300)
        elif bad=='tag':args.update(tag=tag^1024)
        elif bad=='poison':args.update(poison=1)
        elif bad=='reserved':args.update(status=14)
        response(**args);emit(5,a=1);response(tag,1,0,1,0,int.from_bytes(bs[1],'little'));complete(tag,0,mask,expected(bs,mask))
    for status in (1,4,5,7,9,10,11,12,13,14,15):
        reset();alloc(1666,1,255);sent(1666);response(1666,status=status,error=1);emit(5,a=1)
    reset();alloc(1667,3,255);sent(1667);response(1667,0,2,0);response(1667,1,0,0,error=1);emit(5,a=1)
    response(1667,1,2,0);response(1667,2,2,1);complete(1667,0,255,0)
    reset();alloc(1701,2,0);sent(1701);response(1701,1,0,0,data=(1<<512)-1);response(1701,0,0,1,data=(1<<512)-1);complete(1701,0,0,0)
    # Premature response, early LAST with an unseen legal offset, and true multi ordering.
    reset();alloc(1777,4,(1<<256)-1);response(1777,last=0,error=1);sent(1777)
    response(1777,2,0,1,error=1);emit(5,a=1)
    response(1777,1,3,0,error=1);response(1777,0,3,0);response(1777,2,3,0,error=1);emit(5,a=1)
    reset();response(1777,error=1);sent(1777,error=1);emit(5)
    # Shared-kind duplicate allocation and independent same-tag port identity.
    reset();alloc(1901,2,(1<<128)-1);alloc(1901,1,0,write=1,ready=0,error=1);sent(1901)
    response(1901,write=1,error=1);response(1901,0,0,0);response(1901,1,0,1);complete(1901,0,(1<<128)-1,0)
    alloc(1901,1,0,write=1);sent(1901);response(1901,off=3,last=0,status=6,write=1);complete(1901,6,0,0,write=1)
    if capacity>1:
        reset();alloc(2047,2,(1<<128)-1);sent(2047);alloc(2047,1,0,write=1,port=3);sent(2047,3)
        response(2047,1,0,0,data=0x123);response(2047,write=1,port=3);complete(2047,0,0,0,write=1,port=3)
        response(2047,0,0,1,data=0x456);complete(2047,0,(1<<128)-1,(0x123<<512)|0x456)
        reset()
        for k in range(capacity):alloc(1400+k,2,(1<<128)-1);sent(1400+k)
        alloc(1200,1,0,ready=0)
        for k in reversed(range(capacity)):response(1400+k,1,0,0,data=k+17)
        for k in reversed(range(capacity)):
            response(1400+k,0,0,1,data=k+1);complete(1400+k,0,(1<<128)-1,((k+17)<<512)|(k+1))
    emit(5);path.write_text(''.join(rows));return dict(completions=total,events=len(rows))

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--legacy-red',action='store_true');p.add_argument('--faults',action='store_true');a=p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
    stage=ROOT/'build/verification/endpoint_transaction'/a.label;stage.mkdir(parents=True,exist_ok=False)
    sources={'dut.v':(ROOT/'rtl/endpoint/endpoint_tag_table.v').read_bytes(),'tb.sv':Path(__file__).with_name('read_tag_table_tb.sv').read_bytes(),'runner.py':Path(__file__).read_bytes()}
    cases=[('capacity'+str(c),c,None) for c in (1,3,4)]
    if a.faults:cases +=[(name,3,name) for name in ('mask','offset','early','status')]
    result={'passed':True,'legacy_red':a.legacy_red,'cases':[],'sources_sha256':{k:hashlib.sha256(v).hexdigest() for k,v in sources.items()}}
    for name,c,fault in cases:
        out=stage/name;out.mkdir();coverage=fixtures(out/'events.txt',c)
        for filename,blob in sources.items():
            if filename=='dut.v' and fault:
                before,after={
                    'mask':('(response_mask_shifted[response_byte]&&(i_response_status==0))','(1\'b1&&(i_response_status==0))'),
                    'offset':('i_response_offset*512 +: 512','0*512 +: 512'),
                    'early':('r_done[slot]<=i_response_last;','r_done[slot]<=1\'b1;'),
                    'status':('(i_response_status==r_status[response_slot])','1\'b1'),
                }[fault]
                text=blob.decode()
                if text.count(before)!=1:raise ValueError('fault anchor missing/ambiguous '+fault)
                blob=text.replace(before,after).encode()
            (out/filename).write_bytes(blob)
        record=dict(name=name,coverage=coverage,fault=fault)
        for phase,cmd in [('compile',['iverilog','-g2012','-s','tb',f'-Ptb.CAPACITY={c}',*(['-DLEGACY_RED'] if a.legacy_red else []),'-o','sim.vvp','dut.v','tb.sv']),('run',['vvp','sim.vvp'])]:
            with (out/(phase+'.log')).open('w') as log:
                try:code=subprocess.run(cmd,cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=60).returncode
                except subprocess.TimeoutExpired:code=124
            record[phase]=dict(command=cmd,exit=code)
            if phase=='compile' and code:break
        log=(out/'run.log').read_text() if (out/'run.log').exists() else ''
        marker={'mask':'READ_TAG_COMPLETE_BYTES','offset':'READ_TAG_COMPLETE_BYTES','early':'READ_TAG_EARLY_DONE','status':'READ_TAG_RESPONSE'}.get(fault,'READ_TAG_PASS')
        record['passed']=record['compile']['exit']==0 and record.get('run',{}).get('exit')==(1 if fault else 0) and marker in log
        record['artifacts_sha256']={str(f.relative_to(out)):hashlib.sha256(f.read_bytes()).hexdigest() for f in out.iterdir() if f.is_file()}
        result['cases'].append(record);result['passed'] &=record['passed']
    (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result));return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

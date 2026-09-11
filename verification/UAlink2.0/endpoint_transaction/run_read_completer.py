#!/usr/bin/env python3
"""Independent ordinary Read execution regression.

Run: python3 verification/endpoint_transaction/run_read_completer.py --label NEW --capacity 3
Outputs: build/verification/endpoint_transaction/NEW/{result.json,rtl,*.log,vectors.txt}.
Next: connect full Read result and per-Beat responses through the actual transaction path.
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
RED='''module tb; parameter CAPACITY=4;
reg clk=0,rstn=0; wire ready,error;
endpoint_read_completer dut(.i_clk(clk),.i_rstn(rstn),.i_local_id(10'h3a5),
 .i_request_valid(1'b1),.o_request_ready(ready),.i_request_tag(11'h7ff),.i_request_src(10'h301),.i_request_dst(10'h3a5),
 .i_request_address(57'd4),.i_request_length(6'd0),.i_request_attr(8'h05),.i_request_vc(2'd0),.i_request_pool(1'b0),.i_request_asi(2'd0),.i_request_metadata(8'd0),
 .i_mem_ready(1'b0),.i_mem_result_valid(1'b0),.i_mem_result_slot(2'd0),.i_mem_result_data(512'd0),.i_mem_result_status(4'd0),.i_source_captured(1'b0),.i_data_accepted(2'd0),.o_error(error));
initial begin #2;clk=1;#2;clk=0;rstn=1;#2;if(ready!==1'b1||error!==1'b0)$fatal(1,"READ_CAPABILITY_RED ordinary_4byte_rejected");$display("READ_RED_UNEXPECTED_PASS");$finish;end
endmodule
'''

def make_vectors(stage):
    memory=bytes((i*37+(i>>3)*19+(i>>7)*11+7)&255 for i in range(4096))
    (stage/'memory.hex').write_text(''.join(f'{v:02x}\n' for v in memory))
    raw=[]
    for length in range(64):
        for start in range(0,256,4):
            raw.append((start,length,(start*7+length*29)&255,0 if start+4*(length+1)<=256 else 15))
    for attr in range(256):raw.extend([(252,0,attr,0),(60,1,attr,0)])
    for n in range(1,5):
        for status in (0,2,3,6,8):raw.append((0,16*n-1,255,status))
    raw.extend([(1,0,255,15),(2,0,255,15),(3,0,255,15),(0,0,0,0),(252,0,240,0)])
    rows=[];legal=0;beats=0
    for idx,(start,length,attr,status) in enumerate(raw):
        address=start|((1<<56) if idx%3==0 else 0)|((idx%8)<<8)
        size=4*(length+1);n=(start%64+size+63)//64
        valid=status!=15;asi=idx%4;meta=(idx*13+9)&255;tag=(idx*53+1024)&2047;src=(idx*23+513)&1023
        be=0
        if valid:
            for offset in range(size):
                dw=offset//4;enable=((attr>>(offset%4))&1) if dw==0 else ((attr>>(4+offset%4))&1) if dw==length else 1
                if enable:be|=1<<(start+offset)
        data=int.from_bytes(memory[(address&4095)//64*64:(address&4095)//64*64+256],'little')
        expected=data if status==0 else 0
        header=0
        if valid:
            legal+=1;beats+=n
            for beat in range(n):
                literal=(2<<60)|(tag<<47)|(beat<<42)|(status<<38)|(1<<37)|((beat==n-1)<<36)|(0x3a5<<26)|(src<<16)
                header|=literal<<(64*beat)
        vals=[int(valid),address,length,attr,asi,meta,tag,src,status if valid else 0,n,be,data,expected,header]
        rows.append(' '.join(f'{x:x}' for x in vals)+'\n')
    (stage/'vectors.txt').write_text(''.join(rows))
    return len(rows),legal,beats

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--label',required=True);p.add_argument('--capacity',type=int,choices=(1,2,3,4),default=4)
    p.add_argument('--checks',action='store_true',help='also run Verilog-2001, mapped Yosys check and Verilator without waivers');p.add_argument('--legacy-red',action='store_true');p.add_argument('--fault',choices=('data','be','last','early'))
    a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe new label required')
    stage=ROOT/'build/verification/endpoint_transaction'/a.label;stage.mkdir(parents=True,exist_ok=False);(stage/'rtl').mkdir()
    shutil.copyfile(__file__,stage/'runner.py');hashes={};copies=[]
    for name in ('endpoint_read_completer.v','endpoint_response_encode.v'):
        source=ROOT/'rtl/endpoint'/name;data=source.read_bytes();hashes[name]=hashlib.sha256(data).hexdigest()
        if a.fault and name=='endpoint_read_completer.v':
            before,after={
             'data':('full_result_q[slot]<=i_mem_result_data_full;',"full_result_q[slot]<={i_mem_result_data_full[1535:0],i_mem_result_data_full[2047:1536]};"),
             'be':('assign o_mem_be=issue_be;',"assign o_mem_be={issue_be[127:0],issue_be[255:128]};"),
             'last':('.i_offset(head_beat),.i_last(head_final)',".i_offset(head_beat),.i_last(1'b1)"),
             'early':('assign head_result=active&&head_busy&&head_complete;',"assign head_result=active&&head_busy;")
            }[a.fault]
            text=data.decode()
            if text.count(before)!=1:raise ValueError('fault anchor missing/ambiguous')
            data=text.replace(before,after).encode()
        dst=stage/'rtl'/name;dst.write_bytes(data);copies.append(str(dst))
    count,legal,beats=make_vectors(stage)
    tb=RED if a.legacy_red else Path(__file__).with_name('read_completer_tb.sv').read_text().replace('@@COUNT@@',str(count)).replace('@@LEGAL@@',str(legal)).replace('@@BEATS@@',str(beats))
    (stage/'tb.sv').write_text(tb)
    result=dict(capacity=a.capacity,slot_width=2,full_read_enable=0 if a.legacy_red else 1,source_sha256=hashes,fault=a.fault,legacy_red=a.legacy_red,vectors=count,legal_vectors=legal,expected_beats=beats)
    for name,cmd in [('compile',['iverilog','-g2012','-s','tb',f'-Ptb.CAPACITY={a.capacity}','-o','sim.vvp',*copies,'tb.sv']),('run',['vvp','sim.vvp'])]:
        start=time.monotonic()
        with (stage/(name+'.log')).open('w') as log:
            try:rc=subprocess.run(cmd,cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=120).returncode
            except subprocess.TimeoutExpired:rc=124
        result[name]=dict(command=cmd,returncode=rc,seconds=round(time.monotonic()-start,3))
        if name=='compile' and rc:break
    log=(stage/'run.log').read_text() if (stage/'run.log').exists() else ''
    result['passed']=result['compile']['returncode']==0 and result.get('run',{}).get('returncode')==0 and 'READ_COMPLETER_PASS' in log
    if a.fault:result['passed']=result['compile']['returncode']==0 and result.get('run',{}).get('returncode')==1 and any(x in log for x in ('READ_DATA','READ_BE','READ_HEADER','READ_CAUSAL'))
    if a.checks and not a.legacy_red and not a.fault:
        ys='\n'.join(['read_verilog rtl/endpoint_read_completer.v rtl/endpoint_response_encode.v',f'chparam -set FULL_READ_ENABLE 1 -set CAPACITY {a.capacity} -set SLOT_WIDTH 2 endpoint_read_completer','hierarchy -check -top endpoint_read_completer','proc','opt','memory','opt','check -assert','stat','write_json netlist.json'])+'\n'
        (stage/'run.ys').write_text(ys)
        check_commands=[('verilog2001',['iverilog','-g2001','-s','endpoint_read_completer','-Pendpoint_read_completer.FULL_READ_ENABLE=1',f'-Pendpoint_read_completer.CAPACITY={a.capacity}','-Pendpoint_read_completer.SLOT_WIDTH=2','-o','syntax.vvp',*copies]),('yosys',['yosys','-Q','-T','-s','run.ys']),('verilator',['verilator','--lint-only','--language','1364-2001','-Wall','--top-module','endpoint_read_completer','-GFULL_READ_ENABLE=1',f'-GCAPACITY={a.capacity}','-GSLOT_WIDTH=2',*copies])]
        for name,cmd in check_commands:
            start=time.monotonic()
            with (stage/(name+'.log')).open('w') as out:
                try:rc=subprocess.run(cmd,cwd=stage,stdout=out,stderr=subprocess.STDOUT,timeout=120).returncode
                except subprocess.TimeoutExpired:rc=124
            result[name]=dict(command=cmd,returncode=rc,seconds=round(time.monotonic()-start,3))
            result['passed']=result['passed'] and rc==0
        if (stage/'netlist.json').exists():
            net=json.loads((stage/'netlist.json').read_text());types=[v['type'] for m in net['modules'].values() for v in m.get('cells',{}).values()]
            result['mapped_cells']=len(types);result['mapped_latches']=sum('latch' in t for t in types)
            result['passed']=result['passed'] and result['mapped_latches']==0
    result['coverage']={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',log)}
    result['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
    (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');print('PASS' if result['passed'] else 'FAIL',stage/'result.json');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

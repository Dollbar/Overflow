#!/usr/bin/env python3
"""Check actual full ordinary Read / Write Endpoint-Switch transactions.
Run: python3 verification/endpoint_transaction/run_read_endpoint_switch.py --label NEW --kd28-root PATH [--matrix] [--inject] [--bank-depth 1]
Outputs byte-reference fixtures, exact source snapshots, compile/run logs and result.json under build/verification/endpoint_transaction/NEW.
Next inspect full response Beat ownership and application byte masks; single-response TX does not cover multi-response RX.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
BASELINE=r'''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rstn=0;wire ready,error;
endpoint_transaction_core #(.WRITE_ENABLE(1)) dut(.i_clk(clk),.i_rstn(rstn),.i_port(2'd0),.i_local_id(10'd17),
 .i_request_valid(1'b1),.o_request_ready(ready),.i_request_port(2'd0),.i_request_tag(11'd1024),.i_request_address(57'd0),.i_request_dst(10'd513),.i_request_length(6'd0),.i_request_attr(8'h0f),
 .i_request_is_write(1'b0),.i_request_full(1'b0),.i_request_asi(2'd0),.i_request_metadata(8'd0),.i_request_data(2048'd0),.i_request_be(256'd0),
 .i_complete_ready(1'b1),.i_mem_ready(1'b0),.i_mem_result_valid(1'b0),.i_mem_result_slot(2'd0),.i_mem_result_data(512'd0),.i_mem_result_status(4'd0),
 .i_source_captured(2'd0),.i_request_header_taken(1'b0),.i_data_accepted(4'd0),.i_read_valid(1'b0),.i_read_flit(512'd0),.i_read_msg(2'd0),.i_read_classes(6'd0),.i_read_releases(80'd0),
 .i_write_mem_ready(1'b0),.i_write_mem_result_valid(1'b0),.i_write_mem_result_slot(2'd0),.i_write_mem_result_status(4'd0),.o_error(error));
initial begin repeat(3)@(negedge clk);rstn=1;#1;if(!ready||error)$fatal(1,"READ_FULL_UNIMPLEMENTED ready=%b error=%b",ready,error);$display("READ_PROFILE_ACCEPTED");$finish;end
endmodule
'''

def make_program(matrix):
    program=[dict(write=True,full=True,address=0,size=256,attr=0x81,status=0)]
    def read(address,size,attr=255,status=0):program.append(dict(write=False,full=False,address=address,size=size,attr=attr,status=status))
    read(0,4,0x5a);read(60,8,0xa5);read(0,256,0x96);read(128,128,0);read(192,64,0x3c)
    if matrix:
        for dwords in range(1,65):read(4*((dwords*11)%(65-dwords)),4*dwords,((dwords*29)&255))
        for pos in range(64):read(pos*4,4*((pos*7)%(64-pos)+1),(pos*13)&255)
        for attr in range(256):read(124,4,attr)
        for attr in (0,1,0x10,0x12,0x24,0x81,0x96,0xff):read(60,132,attr)
    for status in (0,2,3,6,8):read(0,256,0x5a,status)
    program.append(dict(write=True,full=False,address=60,size=8,attr=0x37,status=0))
    read(0,128,255);read(60,8,0xa5)
    return program

def fixture_files(folder,program):
    descriptions=[];payloads=[];bes=[];masks=[];expected=[];statuses=[];memory_masks=[];num_beats=[];raw_data=[]
    for side in range(2):
        memory=bytearray(256)
        for index,op in enumerate(program):
            address,size=op['address'],op['size'];kind=op['write'];attr=op['attr'];status=op['status'];full=op['full']
            # All source bytes are nonzero so unused Read bytes cannot pass by coincidental zeros.
            blob=bytes(1+((side*73+index*17+byte*11)%255) for byte in range(256))
            asi=(index+side)%4;meta=(index*3+0x5a)&255
            region=0
            if kind:
                for byte in range(address,address+size):
                    if full or (byte+side+index)%3!=1:region|=1<<byte
                for byte in range(address,address+size):
                    if (region>>byte)&1:memory[byte]=blob[byte-(address//64)*64]
                mask=0;result=bytes(256)
            else:
                for byte in range(address,address+size):
                    dword=(byte-address)//4;lane=(byte-address)%4
                    enable=(attr>>lane)&1 if dword==0 else ((attr>>(lane+4))&1 if dword==size//4-1 else 1)
                    if enable:region|=1<<byte
                mask=region>>(64*(address//64))
                result=bytearray(256)
                for byte in range(256):
                    absolute=(address//64)*64+byte
                    if (mask>>byte)&1:result[byte]=memory[absolute]
                if status:mask=0;result=bytes(256)
            raw=bytearray([0xd7]*256)
            if not kind:
                for byte in range(64*(((address%64)+size+63)//64)):raw[byte]=memory[(address//64)*64+byte]
            else:raw=bytes(256)
            raw_data.append(bytes(raw)[::-1].hex())
            desc=(int(kind)<<93)|(int(full)<<92)|((1024+index)<<81)|(address<<24)|((size//4-1)<<18)|(attr<<10)|(asi<<8)|meta
            descriptions.append(f'{desc:024x}');payloads.append(blob[::-1].hex());bes.append(f'{(0 if full else region):064x}');memory_masks.append(f'{region:064x}');masks.append(f'{mask:064x}');expected.append(bytes(result)[::-1].hex());statuses.append(f'{status:x}');num_beats.append(f'{((address%64)+size+63)//64:x}')
    for name,values in [('descriptors',descriptions),('payloads',payloads),('byte_enables',bes),('memory_masks',memory_masks),('expected_masks',masks),('expected_data',expected),('statuses',statuses),('num_beats',num_beats),('expected_raw',raw_data)]:
        (folder/(name+'.hex')).write_text('\n'.join(values)+'\n')
    (folder/'program.json').write_text(json.dumps(program,indent=2)+'\n')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--kd28-root',type=Path)
    p.add_argument('--legacy-red',action='store_true');p.add_argument('--matrix',action='store_true');p.add_argument('--inject',action='store_true');p.add_argument('--bank-depth',type=int,choices=(1,3),default=3)
    p.add_argument('--fault',choices=('mask_ignored','upper_data_lost'));a=p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
    if not a.legacy_red and a.kd28_root is None:p.error('explicit --kd28-root required for actual ESE')
    out=ROOT/'build/verification/endpoint_transaction'/a.label;out.mkdir(parents=True,exist_ok=False)
    cached={};manifest=ROOT/'third_party/kd28_dependency.json';manifest_bytes=manifest.read_bytes()
    if not a.legacy_red:
        for relative,h in json.loads(manifest_bytes)['functional_sources_sha256'].items():
            path=a.kd28_root.resolve()/relative;blob=path.read_bytes()
            if hashlib.sha256(blob).hexdigest()!=h:raise ValueError('dependency hash mismatch: '+relative)
            cached[path]=blob
    sources=sorted((ROOT/'rtl').rglob('*.v'))+list(cached)
    tb=ROOT/'verification/endpoint_transaction/read_endpoint_switch_tb.sv'
    if not a.legacy_red:sources.append(tb)
    copies=[];hashes={};mapping={};mutations={}
    for index,source in enumerate(sources):
        dest=out/'sources'/(str(index)+'_'+source.name);dest.parent.mkdir(exist_ok=True);blob=cached[source] if source in cached else source.read_bytes()
        if a.fault=='mask_ignored' and source.name=='endpoint_tag_table.v':
            anchor=b'if(response_mask_shifted[response_byte]&&(i_response_status==0))'
            if blob.count(anchor)!=1:raise ValueError('mask mutation anchor changed')
            mutations[str(source)]={'original_sha256':hashlib.sha256(blob).hexdigest(),'removed':'per-byte allocation mask condition'}
            blob=blob.replace(anchor,b'if(i_response_status==0)')
        dest.write_bytes(blob);copies.append(dest)
        hashes[str(source)]=hashlib.sha256(blob).hexdigest();mapping[str(source)]=str(dest.relative_to(out))
    for source,name,blob in [(Path(__file__),'runner.py',Path(__file__).read_bytes()),(manifest,'dependency.json',manifest_bytes)]:
        (out/name).write_bytes(blob);hashes[str(source)]=hashlib.sha256(blob).hexdigest();mapping[str(source)]=name
    if a.legacy_red:(out/'tb.sv').write_text(BASELINE);copies.append(out/'tb.sv');program=[]
    else:program=make_program(a.matrix);fixture_files(out,program)
    parameters=[] if a.legacy_red else [f'-Ptb.COUNT={len(program)}',f'-Ptb.INJECT={int(a.inject)}',f'-Ptb.BANK_DEPTH={a.bank_depth}',f'-Ptb.FAULT={ {None:0,"mask_ignored":1,"upper_data_lost":2}[a.fault]}']
    command=['iverilog','-g2012','-s','tb',*parameters,'-o',str(out/'sim.vvp'),*map(str,copies)]
    result={'passed':False,'legacy_red':a.legacy_red,'matrix':a.matrix,'bank_depth':a.bank_depth,'inject':a.inject,'fault':a.fault,'requests_per_side':len(program),'sources':hashes,'snapshot_sources':mapping,'mutations':mutations}
    for phase,cmd in [('compile',command),('run',['vvp',str(out/'sim.vvp')])]:
        result[phase+'_command']=cmd
        with (out/(phase+'.log')).open('w') as log:
            try:code=subprocess.run(cmd,cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=240).returncode
            except subprocess.TimeoutExpired:code=124
        result[phase+'_exit']=code
        if phase=='compile' and code:break
    log=(out/'run.log').read_text() if (out/'run.log').exists() else ''
    marker='READ_FULL_UNIMPLEMENTED' if a.legacy_red else 'READ_ESE_COMPLETE_DATA' if a.fault else 'READ_ESE_PASS'
    result['passed']=result.get('compile_exit')==0 and result.get('run_exit')==(1 if a.legacy_red or a.fault else 0) and marker in log
    result['artifacts_sha256']={str(f.relative_to(out)):hashlib.sha256(f.read_bytes()).hexdigest() for f in out.rglob('*') if f.is_file()};(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k in ('passed','compile_exit','run_exit','requests_per_side')}));return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

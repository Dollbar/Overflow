#!/usr/bin/env python3
"""Run real Endpoint/Switch causal Read transactions without response fixtures.
Run: python3 verification/endpoint_transaction/run_transactions.py --kd28-root PATH --label NEW [--inject] [--bank-depth N]
Outputs source snapshots, command/return-code logs and result.json in build/verification/endpoint_transaction/NEW.
Next inspect actual request, memory-result, response and completion ownership before expanding profiles.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = (lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
BASELINE = '''module tb; parameter INJECT=0, BANK_DEPTH=3;
reg clk=0; always #5 clk=~clk;
reg rstn=0; wire ready,implemented;
endpoint_transaction_core dut(.i_clk(clk),.i_rstn(rstn),.i_enable(1'b1),.i_valid(1'b1),
.i_data(512'd0),.i_meta(128'd0),.o_ready(ready),.o_implemented(implemented));
initial begin #12;rstn=1;#20;if(!ready||!implemented)$fatal(1,"UNIMPLEMENTED_TRANSACTION_CORE");$finish;end
endmodule
'''

VIP_SELFTEST = r'''`timescale 1ns/1ps
module tb;
parameter INJECT=0,BANK_DEPTH=3;
import ualink_test_pkg::*;
reg clk=0;always #5 clk=~clk;
reg rstn=0,read_valid=0,result_ready=0;
reg [1:0] read_slot=0;reg [56:0] read_address=0;
wire read_ready,result_valid;wire [1:0] result_slot;
wire [511:0] result_data;wire [3:0] result_status;
ualink_memory_vip #(.SIDE(0),.MIN_LATENCY(2),.SLOT_LATENCY_STEP(1)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_read_valid(read_valid),.o_read_ready(read_ready),
 .i_read_slot(read_slot),.i_read_address(read_address),.i_read_length(6'd15),
 .i_read_attr(8'hff),.i_read_asi(2'd0),.i_read_metadata(8'd0),
 .o_result_valid(result_valid),.i_result_ready(result_ready),.o_result_slot(result_slot),
 .o_result_data(result_data),.o_result_status(result_status));
reg [3:0] active=0,seen=0;
reg held=0;reg [518:0] held_value;
integer cycles=0,requests=0,returns=0;
function [511:0] expected;
 input [1:0] slot;
 begin
  case(slot)
   0:expected=512'h6e5c4a38261402f0deccbaa8968472604e3c2a1806f4e2d0beac9a88766452402e1c0af8e6d4c2b09e8c7a68564432200efcead8c6b4a2907e6c5a4836241200;
   1:expected=512'h8a7a665642321e0efaead6c6b2a28e7e6a5a46362212feeedacab6a692826e5e4a3a261602f2decebaaa968672624e3e2a1a06f6e2d2beae9a8a766652422e1e;
   2:expected=512'ha69486745e4c3e2c1604f6e4cebcae9c867466543e2c1e0cf6e4d6c4ae9c8e7c665446341e0cfeecd6c4b6a48e7c6e5c46342614feecdeccb6a496846e5c4e3c;
   default:expected=512'd0;
  endcase
 end
endfunction
always @(posedge clk)begin
 cycles=cycles+1;
 if(cycles>150)$fatal(1,"VIP_SELFTEST_TIMEOUT");
 if(!rstn)begin
  if(read_ready!==0||result_valid!==0)$fatal(1,"VIP_SELFTEST_RESET_OUTPUT");
  active=0;seen=0;held=0;
 end else begin
  if(held&&held_value!=={result_valid,result_slot,result_data,result_status})$fatal(1,"VIP_SELFTEST_RESULT_STABILITY");
  held=result_valid&&!result_ready;held_value={result_valid,result_slot,result_data,result_status};
  if(read_valid&&read_ready)begin
   if(active[read_slot])$fatal(1,"VIP_SELFTEST_SLOT_REUSE");
   active[read_slot]=1;requests=requests+1;
  end
  if(result_valid)begin
   if(!active[result_slot]||seen[result_slot]||result_data!==expected(result_slot)||result_status!==((result_slot==3)?4'd3:4'd0))
    $fatal(1,"VIP_SELFTEST_RESULT_DATA");
   if(result_ready)begin active[result_slot]=0;seen[result_slot]=1;returns=returns+1;end
  end
 end
end
task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
task send;
 input [1:0] slot;input [56:0] address;
 begin
  read_slot=slot;read_address=address;read_valid=1;#1;
  while(!read_ready)tick;
  tick;read_valid=0;
 end
endtask
initial begin
 repeat(2)tick;rstn=1;
 if(tag_at(2)!==11'd1024||tag_at(3)!==11'd2044||address_at(7)!==57'h100000000000000||tag_index(11'd123)!=-1||address_index(57'd3)!=-1)
  $fatal(1,"VIP_SELFTEST_PACKAGE_FIXTURES");
 send(0,57'd0);while(!result_valid)tick;
 send(1,57'd64);send(2,57'd128);send(3,57'h100000000000000);
 read_slot=0;#1;if(read_ready!==0)$fatal(1,"VIP_SELFTEST_RESULT_SLOT_RELEASED_EARLY");
 repeat(12)tick;
 result_ready=1;repeat(20)tick;result_ready=0;
 if(requests!=4||returns!=4||seen!==4'b1111||active!==0)$fatal(1,"VIP_SELFTEST_DRAIN");
 // Reset cancels an accepted command before its due result, without exporting service state.
 send(0,57'd0);rstn=0;tick;rstn=1;repeat(20)tick;
 if(result_valid!==0||requests!=5||returns!=4)$fatal(1,"VIP_SELFTEST_RESET_CANCEL");
 $display("VIP_MEMORY_PASS requests=5 results=4 reset_cancel=1 four_slots=1 held_results=1 cycles=%0d",cycles);
 $finish;
end
endmodule
'''


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--label',required=True);p.add_argument('--kd28-root',type=Path)
    p.add_argument('--inject',action='store_true');p.add_argument('--bank-depth',type=int,default=3)
    p.add_argument('--vip-selftest',action='store_true',help='Run four-slot memory VIP holding/reset test without KD28')
    p.add_argument('--shell-baseline',action='store_true');p.add_argument('--fault',choices=['data_half','retirement','tag_high'])
    a=p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',a.label):p.error('safe new label required')
    if not 1<=a.bank_depth<=16:p.error('bank-depth must be 1..16')
    if a.vip_selftest and (a.shell_baseline or a.fault or a.inject):p.error('VIP selftest is separate from transaction and fault scenarios')
    stage=ROOT/'build/verification/endpoint_transaction'/a.label;stage.mkdir(parents=True,exist_ok=False)
    srcdir=stage/'rtl';srcdir.mkdir()
    if a.shell_baseline:
        sources=[ROOT/'rtl/endpoint/endpoint_transaction_core.v'];tb=BASELINE
    elif a.vip_selftest:
        sources=[ROOT/'verification/pkg/ualink_test_pkg.sv',ROOT/'simulator/vip/ualink_memory_vip.sv'];tb=VIP_SELFTEST
    else:
        if a.kd28_root is None:p.error('explicit --kd28-root required')
        dep=a.kd28_root.resolve();manifest=json.loads((ROOT/'third_party/kd28_dependency.json').read_text())
        dependencies=[]
        for rel,h in manifest['functional_sources_sha256'].items():
            path=dep/rel
            if hashlib.sha256(path.read_bytes()).hexdigest()!=h:raise ValueError('dependency hash mismatch: '+rel)
            dependencies.append(path)
        sources=[ROOT/'verification/pkg/ualink_test_pkg.sv',ROOT/'simulator/vip/ualink_memory_vip.sv']+sorted((ROOT/'rtl').rglob('*.v'))+dependencies
        tb=(ROOT/'verification/endpoint_transaction/transactions_tb.sv').read_text()
    copies=[];hashes={}
    for index,path in enumerate(sources):
        dest=(stage/'support'/(str(index)+'_'+path.name)) if path.suffix=='.sv' else srcdir/(str(index)+'_'+path.name)
        dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,dest);copies.append(dest)
        mutations={
            'data_half':('endpoint_transaction_core.v', 'assign o_data1={completer_data[511:256],256\'d0};', 'assign o_data1={256\'d0,256\'d0};'),
            'retirement':('ualink_endpoint_top.v', '.i_read_ready(selected_read_ready),.o_read_valid(o_read_valid)', '.i_read_ready(1\'b1),.o_read_valid(o_read_valid)'),
            'tag_high':('endpoint_transaction_core.v', '.i_response_tag(response_tag)', '.i_response_tag({1\'b0,response_tag[9:0]})')}
        if a.fault and path.name==mutations[a.fault][0]:
            _,before,after=mutations[a.fault];text=dest.read_text()
            if text.count(before)!=1:raise ValueError('fault anchor missing/ambiguous')
            dest.write_text(text.replace(before,after))
        hashes[str(path)]=hashlib.sha256(path.read_bytes()).hexdigest()
    for path in [Path(__file__),ROOT/'config/ip_module_inventory.json']+([] if a.shell_baseline else [ROOT/'verification/endpoint_transaction/transactions_tb.sv']):
        hashes[str(path)]=hashlib.sha256(path.read_bytes()).hexdigest()
    (stage/'tb.sv').write_text(tb)
    command=['iverilog','-g2012','-s','tb',f'-Ptb.INJECT={int(a.inject)}',f'-Ptb.BANK_DEPTH={a.bank_depth}',
             '-o',str(stage/'sim.vvp'),*map(str,copies),str(stage/'tb.sv')]
    result=dict(passed=False,shell_baseline=a.shell_baseline,vip_selftest=a.vip_selftest,inject=a.inject,bank_depth=a.bank_depth,
                fault=a.fault,scope=('four-slot memory VIP holding/reset behavior; local test memory' if a.vip_selftest else 'actual causal single64B Read RTL; local DL record and explicit CRC status, not standard framing'),sources=hashes,source_order=[str(path) for path in sources],snapshot_sources={str(path):str(copy.relative_to(stage)) for path,copy in zip(sources,copies)})
    for name,cmd in [('compile',command),('run',['vvp',str(stage/'sim.vvp')])]:
        result[name+'_command']=cmd
        with (stage/(name+'.log')).open('w') as log:
            try:code=subprocess.run(cmd,cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=180).returncode
            except subprocess.TimeoutExpired:code=124
        result[name+'_exit']=code
        if code and name=='compile':break
    log=(stage/'run.log').read_text() if (stage/'run.log').exists() else ''
    result['passed']=(result.get('compile_exit')==0 and result.get('run_exit')==1 and 'UNIMPLEMENTED_TRANSACTION_CORE' in log) if a.shell_baseline else (result.get('run_exit')==0 and 'CAUSAL_READ_PASS' in log)
    if a.vip_selftest:
        result['passed']=result.get('compile_exit')==0 and result.get('run_exit')==0 and 'VIP_MEMORY_PASS' in log
    if a.fault:
        result['passed']=result.get('compile_exit')==0 and result.get('run_exit')==1 and any(x in log for x in {'data_half':['CAUSAL_COMPLETION_DATA'],'tag_high':['CAUSAL_DUT_ERROR'],'retirement':['CAUSAL_DUT_ERROR','CAUSAL_TIMEOUT','CAUSAL_COMPLETION_DATA']}[a.fault])
    result['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
    (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k in ('passed','shell_baseline','compile_exit','run_exit')}))
    return 0 if result['passed'] else 1

if __name__=='__main__':raise SystemExit(main())

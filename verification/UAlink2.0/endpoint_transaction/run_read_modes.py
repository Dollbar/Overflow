"""Check full-Read-only mode rejects Write and accepts a partial Read through actual core.
Run: python3 verification/endpoint_transaction/run_read_modes.py --label NEW
Outputs source/TB snapshots, command logs and result.json in build/verification/endpoint_transaction/NEW.
Next run the dual Endpoint/Switch test for full data/memory causality.
"""
from pathlib import Path
import argparse,hashlib,json,re,subprocess
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
TB=r'''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rstn=0,valid=0,write=0;wire ready,error,complete,kind,cv;wire[2047:0]data;wire[255:0]mask;wire[10:0]tag;wire[3:0]status;
wire[1:0]source;wire[511:0]control;wire[3:0]dv;wire[7:0]count,wcount;wire wmem,wrr;
endpoint_transaction_core #(.FULL_READ_ENABLE(1),.WRITE_ENABLE(0)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_local_id(10'd17),.i_port(2'd0),
 .i_request_valid(valid),.o_request_ready(ready),.i_request_is_write(write),.i_request_full(1'b0),.i_request_port(2'd0),.i_request_tag(11'd1024),.i_request_address(57'd60),.i_request_dst(10'd513),.i_request_length(6'd1),.i_request_attr(8'ha5),.i_request_asi(2'd3),.i_request_metadata(8'h9c),.i_request_data(2048'd0),.i_request_be(256'd0),
 .o_complete_valid(complete),.i_complete_ready(1'b0),.o_complete_is_write(kind),.o_complete_data_valid(cv),.o_complete_data_full(data),.o_complete_mask(mask),.o_complete_tag(tag),.o_complete_status(status),
 .o_source_valid(source),.o_source_control(control),.i_source_captured(2'd0),.i_request_header_taken(1'b0),.o_data_valid(dv),.i_data_accepted(4'd0),
 .i_read_valid(1'b0),.i_read_flit(512'd0),.i_read_msg(2'd0),.i_read_classes(6'd0),.i_read_releases(80'd0),
 .i_mem_ready(1'b0),.i_mem_result_valid(1'b0),.i_mem_result_slot(2'd0),.i_mem_result_data(512'd0),.i_mem_result_data_full(2048'd0),.i_mem_result_status(4'd0),
 .o_write_mem_valid(wmem),.o_write_mem_result_ready(wrr),.i_write_mem_ready(1'b0),.i_write_mem_result_valid(1'b0),.i_write_mem_result_slot(2'd0),.i_write_mem_result_status(4'd0),.o_write_completer_count(wcount),.o_outstanding_count(count),.o_error(error));
integer i;
initial begin
 repeat(3)@(negedge clk);rstn=1;write=1;valid=1;
 repeat(8)begin @(negedge clk);if(ready!==0||error!==1||source!==0||dv!==0||count!==0||wmem!==0||wrr!==0||wcount!==0||complete!==0)$fatal(1,"READ_ONLY_WRITE_NOT_REJECTED");end
 rstn=0;valid=0;repeat(3)@(negedge clk);rstn=1;write=0;valid=1;#1;
 if(ready!==1||error!==0)$fatal(1,"READ_ONLY_READ_NOT_ACCEPTED");
 @(negedge clk);valid=0;#1;
 if(count!==1||source[0]!==1||control[123:118]!==6'd3||control[93:88]!==6'd1||control[101:94]!==8'ha5||control[115:114]!==2'd3||control[87:80]!==8'h9c||control[4:0]!==0||dv!==0||error!==0)$fatal(1,"READ_ONLY_REQUEST_FIELDS");
 repeat(8)begin @(negedge clk);if(source[0]!==1||count!==1||complete!==0||wmem!==0||wrr!==0||error!==0)$fatal(1,"READ_ONLY_HOLD");end
 $display("READ_ONLY_MODE_PASS rejected_write_cycles=8 read_reservations=1");$finish;
end
endmodule
'''
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe new label required')
 stage=ROOT/'build/verification/endpoint_transaction'/a.label;stage.mkdir(parents=True,exist_ok=False)
 paths=list((ROOT/'rtl/endpoint').glob('*.v'))+[ROOT/'rtl/tl/tl_control_decode.v'];copies=[];hashes={}
 for src in paths:
  raw=src.read_bytes();dst=stage/src.name;dst.write_bytes(raw);copies.append(dst);hashes[str(src)]=hashlib.sha256(raw).hexdigest()
 (stage/'tb.sv').write_text(TB);(stage/'runner.py').write_bytes(Path(__file__).read_bytes());result={'passed':False,'sources':hashes}
 c=['iverilog','-g2012','-s','tb','-o',str(stage/'sim.vvp'),str(stage/'tb.sv'),*map(str,copies)]
 for name,cmd in [('compile',c),('run',['vvp',str(stage/'sim.vvp')])]:
  with (stage/(name+'.log')).open('w') as log:code=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=120).returncode
  result[name+'_exit']=code;result[name+'_command']=cmd
  if code:break
 result['passed']=result.get('compile_exit')==0 and result.get('run_exit')==0 and 'READ_ONLY_MODE_PASS' in (stage/'run.log').read_text()
 result['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()};(stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(result['passed']);return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

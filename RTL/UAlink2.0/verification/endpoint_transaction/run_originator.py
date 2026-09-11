#!/usr/bin/env python3
"""Originator / Tag-table actual RTL checks; use --label for fresh retained evidence.

Red baseline: python3 verification/endpoint_transaction/run_originator.py --label originator_red --shell-baseline
Outputs: build/verification/endpoint_transaction/LABEL/{result.json,*/run.log,*/tb.sv,*/RTL}
Run implemented checks: python3 verification/endpoint_transaction/run_originator.py --label originator_final --faults
Next: connect actual receiver and TL source_captured/header_taken events in the Endpoint core.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
MODULES = ("endpoint_read_originator", "endpoint_tag_table")


def shell_tb(module):
    return f"""`timescale 1ns/1ps
module tb;
reg clk=0;
always #5 clk=~clk;
reg rstn=0, valid=0;
wire ready, error;
{module} dut(.i_clk(clk),.i_rstn(rstn),.i_enable(1'b1),.i_valid(valid),
 .i_data(512'd0),.i_meta(128'd0),.o_ready(ready),.o_error(error));
initial begin
 repeat(2) @(negedge clk);
 rstn=1; valid=1;
 #1;
 if (ready !== 1'b1 || error !== 1'b0)
   $fatal(1,"ORIGINATOR_SCOREBOARD missing first reservation: ready=%b error=%b",ready,error);
 $display("PASS shell reservation");
 $finish;
end
endmodule
"""


TB = r'''`timescale 1ns/1ps
module tb;
localparam PORTS=__PORTS__;
reg clk=0;
always #5 clk=~clk;
reg rstn=0;
reg [9:0] local_id=10'd1023;
reg request_valid=0;
wire request_ready;
reg [1:0] request_port=0;
reg [10:0] request_tag=0;
reg [56:0] request_address=0;
reg [9:0] request_dst=10'd1022;
reg [5:0] request_length=15;
reg [7:0] request_attr=255;
wire source_valid;
wire [255:0] source_control;
reg source_captured=0,header_taken=0;
reg response_valid=0;
wire response_ready;
reg [1:0] response_port=0;
reg [10:0] response_tag=0;
reg [9:0] response_dst=10'd1023;
reg [3:0] response_status=0;
reg [1:0] response_offset=0,response_num_beats=0;
reg response_last=1,response_data_error=0;
reg [511:0] response_data=0;
wire complete_valid,complete_data_valid,error;
reg complete_ready=0;
wire [1:0] complete_port;
wire [10:0] complete_tag;
wire [3:0] complete_status;
wire [511:0] complete_data;
wire [7:0] count;
endpoint_read_originator #(.CAPACITY(4),.NUM_PORTS(PORTS)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_local_id(local_id),
 .i_request_valid(request_valid),.o_request_ready(request_ready),
 .i_request_port(request_port),.i_request_tag(request_tag),.i_request_address(request_address),
 .i_request_dst(request_dst),.i_request_length(request_length),.i_request_attr(request_attr),
 .o_source_valid(source_valid),.o_source_control(source_control),.i_source_captured(source_captured),.i_header_taken(header_taken),
 .i_response_valid(response_valid),.o_response_ready(response_ready),.i_response_port(response_port),
 .i_response_tag(response_tag),.i_response_dst(response_dst),.i_response_status(response_status),
 .i_response_offset(response_offset),.i_response_last(response_last),.i_response_num_beats(response_num_beats),
 .i_response_data(response_data),.i_response_data_error(response_data_error),
 .o_complete_valid(complete_valid),.i_complete_ready(complete_ready),.o_complete_port(complete_port),
 .o_complete_tag(complete_tag),.o_complete_status(complete_status),.o_complete_data(complete_data),
 .o_complete_data_valid(complete_data_valid),.o_error(error),.o_count(count));

// 独立记录按完整(port,Tag)寻址，不复制RTL槽选择或完成仲裁实现。
reg active[0:8191],sent[0:8191],done[0:8191];
reg [511:0] results[0:8191];
reg [3:0] statuses[0:8191];
integer occupancy=0,pending_key=0,request_key,response_key,complete_key,j;
reg pending=0,captured=0;
reg [255:0] pending_word=0;
reg req_legal,req_ready_expected,rsp_legal,err_expected;
reg held=0;
reg [530:0] held_completion;
integer cycles=0,reservations=0,sends=0,responses=0,retirements=0,diagnostics=0,resets=0;
function [255:0] request_word;
 input [10:0] tag;
 input [56:0] address;
 input [9:0] dst;
 reg [255:0] word;
 begin
  // 固定Table5-29基础hex；各可变位独立覆盖，无模型encode/decode参与。
  word=256'h0000000000000000000000000000000010c0003fcf0000000000000000000000;
  word[113:103]=tag; word[79:25]=address[56:2];
  word[24:15]=10'd1023; word[14:5]=dst;
  request_word=word;
 end
endfunction
function [511:0] payload;
 input integer seed;
 integer b;
 begin
  for(b=0;b<64;b=b+1) payload[b*8+:8]=(seed+13*b+(b*b))&255;
 end
endfunction
always @(posedge clk) begin
 cycles=cycles+1;
 if (!rstn) begin
  if ({request_ready,source_valid,source_control,response_ready,complete_valid,complete_port,
       complete_tag,complete_status,complete_data,complete_data_valid,error,count} !== 0)
   $fatal(1,"ORIGINATOR_SCOREBOARD reset outputs");
  for(j=0;j<8192;j=j+1) begin active[j]=0;sent[j]=0;done[j]=0; end
  occupancy=0;pending=0;captured=0;held=0;resets=resets+1;
 end else begin
  request_key=request_port*2048+request_tag;
  response_key=response_port*2048+response_tag;
  complete_key=complete_port*2048+complete_tag;
  req_legal=(request_port<PORTS && request_address[5:0]==0 && request_length==15 && request_attr==255);
  req_ready_expected=req_legal && !pending && !active[request_key] && occupancy<4;
  rsp_legal=(response_port<PORTS && response_dst==local_id && (response_status==0 || response_status==3) &&
             response_offset==0 && response_num_beats==0 && response_last && !response_data_error &&
             active[response_key] && sent[response_key] && !done[response_key]);
  err_expected=(request_valid && (!req_legal || (!pending && active[request_key]))) ||
               (source_captured && (!pending || captured)) ||
               (header_taken && (!pending || (!captured && !source_captured))) ||
               (response_valid && !rsp_legal);
  if (count !== occupancy[7:0] || request_ready !== req_ready_expected || response_ready !== 1'b1 || error !== err_expected)
   $fatal(1,"ORIGINATOR_SCOREBOARD flags cycle=%0d count=%0d expected=%0d ready=%b/%b err=%b/%b",cycles,count,occupancy,request_ready,req_ready_expected,error,err_expected);
  if (source_valid !== (pending&&!captured) || source_control !== ((pending&&!captured)?pending_word:256'd0))
   $fatal(1,"ORIGINATOR_SCOREBOARD source ownership cycle=%0d",cycles);
  if (held && {complete_valid,complete_port,complete_tag,complete_status,complete_data_valid,complete_data} !== held_completion)
   $fatal(1,"ORIGINATOR_SCOREBOARD completion changed under backpressure");
  held=complete_valid&&!complete_ready;
  held_completion={complete_valid,complete_port,complete_tag,complete_status,complete_data_valid,complete_data};
  if (complete_valid) begin
   if (!active[complete_key] || !sent[complete_key] || !done[complete_key] ||
       complete_status !== statuses[complete_key] || complete_data_valid !== (statuses[complete_key]==0) ||
       complete_data !== ((statuses[complete_key]==0)?results[complete_key]:512'd0))
    $fatal(1,"ORIGINATOR_SCOREBOARD completion correlation tag=%0d port=%0d",complete_tag,complete_port);
  end else if ({complete_port,complete_tag,complete_status,complete_data_valid,complete_data} !== 0)
   $fatal(1,"ORIGINATOR_SCOREBOARD invalid completion not zero");
  // 响应合法性取沿前已发送状态；同拍Header消费不允许倒算先到响应。
  if (response_valid && rsp_legal) begin
   done[response_key]=1;results[response_key]=response_data;statuses[response_key]=response_status;responses=responses+1;
  end
  if (source_captured && pending && !captured) captured=1;
  if (header_taken && pending && captured) begin sent[pending_key]=1;pending=0;captured=0;sends=sends+1;end
  if (request_valid && request_ready) begin
   active[request_key]=1;sent[request_key]=0;done[request_key]=0;occupancy=occupancy+1;
   pending=1;captured=0;pending_key=request_key;pending_word=request_word(request_tag,request_address,request_dst);
   reservations=reservations+1;
  end
  if (complete_valid && complete_ready) begin active[complete_key]=0;done[complete_key]=0;occupancy=occupancy-1;retirements=retirements+1;end
  if(error)diagnostics=diagnostics+1;
 end
 if(cycles>1000)$fatal(1,"ORIGINATOR_SCOREBOARD watchdog");
end

task step;
 begin @(posedge clk);#1;@(negedge clk);end
endtask
task allocate;
 input [1:0] port;
 input [10:0] tag;
 input [56:0] address;
 begin
  request_port=port;request_tag=tag;request_address=address;request_valid=1;
  #1;if(request_ready!==1'b1)$fatal(1,"ORIGINATOR_SCOREBOARD missing reservation tag=%0d",tag);
  step;request_valid=0;
 end
endtask
task capture;
 begin source_captured=1;step;source_captured=0;end
endtask
task transmit;
 begin header_taken=1;step;header_taken=0;end
endtask
task send_request;
 input [1:0] port;
 input [10:0] tag;
 input [56:0] address;
 begin allocate(port,tag,address);repeat(2)step;capture;repeat(2)step;transmit;end
endtask
task respond;
 input [1:0] port;
 input [10:0] tag;
 input [3:0] status;
 input integer seed;
 begin
  response_port=port;response_tag=tag;response_status=status;response_data=payload(seed);response_valid=1;
  step;response_valid=0;
 end
endtask
task drain;
 begin
  complete_ready=1;repeat(20)step;complete_ready=0;
  if(count!==0 || complete_valid!==0)$fatal(1,"ORIGINATOR_SCOREBOARD drain failed");
 end
endtask
initial begin
 repeat(2)step;rstn=1;
 // 非法profile不预约；idle非法字段无诊断。
 request_address=57'd3;request_valid=1;step;request_valid=0;step;request_address=0;
 request_length=0;request_valid=1;step;request_valid=0;request_length=15;
 request_attr=0;request_valid=1;step;request_valid=0;request_attr=255;
 if(PORTS<4)begin request_port=PORTS;request_valid=1;step;request_valid=0;request_port=0;end
 // 完整地址高位和capture/实际发送间的响应拒绝。
 allocate(0,0,57'h100000000000000);repeat(6)step;
 respond(0,0,0,1);capture;respond(0,0,0,2);
 source_captured=1;step;source_captured=0;
 repeat(3)step;transmit;
 header_taken=1;step;header_taken=0;
 source_captured=1;step;source_captured=0;
 send_request(0,4,57'h12340);
 send_request(0,1024,57'h1ffffffffffffc0);
 send_request(0,2044,57'd64);
 // 四个同低两位Tag实际在途；正常full背压不报错。
 request_tag=7;request_address=0;request_valid=1;repeat(4)step;request_valid=0;
 if(count!==4)$fatal(1,"ORIGINATOR_SCOREBOARD capacity less than four");
 // 后到低槽完成不能替换已经背压保持的高槽完成。
 respond(0,2044,0,33);repeat(4)step;
 respond(0,0,0,49);repeat(3)step;
 respond(0,2044,0,88);
 response_dst=0;respond(0,4,0,99);response_dst=1023;
 respond(0,2023,0,100);
 respond(0,4,4,101);
 response_offset=1;respond(0,4,0,102);response_offset=0;
 response_last=0;respond(0,4,0,103);response_last=1;
 response_num_beats=1;respond(0,4,0,104);response_num_beats=0;
 response_data_error=1;respond(0,4,0,105);response_data_error=0;
 if(PORTS<4)respond(PORTS,4,0,106);
 respond(0,4,3,199);respond(0,1024,0,201);
 request_tag=0;request_valid=1;step;request_valid=0;
 repeat(5)step;drain;
 // 退休后复用完整Tag；无valid的Data变化不得完成。
 send_request(0,0,57'd128);response_data=payload(5);repeat(5)step;
 if(complete_valid!==0 || count!==1)$fatal(1,"ORIGINATOR_SCOREBOARD no response valid completed");
 respond(0,0,0,203);repeat(3)step;drain;
 // 申请、另一Tag响应和旧完成退休同拍，容量与三个所有者各自守恒。
 send_request(0,1,57'd64);send_request(0,5,57'd128);send_request(0,9,57'd192);
 respond(0,9,0,209);repeat(3)step;
 complete_ready=1;response_port=0;response_tag=1;response_status=0;response_data=payload(210);response_valid=1;
 allocate(0,13,57'd256);complete_ready=0;response_valid=0;
 capture;transmit;respond(0,5,0,211);respond(0,13,3,212);drain;
 // 同Tag不同端口独立；NUM_PORTS只改变身份域，不扩大共享四槽容量。
 if(PORTS>1)begin
  send_request(0,1023,57'd0);send_request(PORTS-1,1023,57'd64);
  respond(PORTS-1,1023,0,77);respond(0,1023,0,88);drain;
 end
 // reset分别取消待capture、capture后未发送、已完成背压及已sent等待响应。
 allocate(0,31,57'd0);rstn=0;step;rstn=1;step;
 allocate(0,31,57'd64);capture;rstn=0;step;rstn=1;step;
 send_request(0,31,57'd128);respond(0,31,0,220);repeat(3)step;rstn=0;step;rstn=1;step;
 send_request(0,31,57'd192);rstn=0;step;rstn=1;step;
 respond(0,31,0,221);
 send_request(0,31,57'd256);respond(0,31,3,222);drain;
 if(reservations !== ((PORTS>1)?16:14) || sends !== ((PORTS>1)?14:12) ||
    responses !== ((PORTS>1)?13:11) || retirements !== ((PORTS>1)?12:10) || diagnostics !== ((PORTS==4)?18:20))
  $fatal(1,"ORIGINATOR_SCOREBOARD insufficient executed events");
 $display("PASS ports=%0d cycles=%0d reservations=%0d sent=%0d responses=%0d retired=%0d diagnostics=%0d reset_edges=%0d",PORTS,cycles,reservations,sends,responses,retirements,diagnostics,resets);
 $finish;
end
endmodule
'''


MUTATIONS = [
    ("capture_is_sent", "endpoint_read_originator", "assign sent_event=i_header_taken", "assign sent_event=i_source_captured"),
    ("response_tag_alias", "endpoint_tag_table", "(r_tag[scan_slot]==i_response_tag)", "(r_tag[scan_slot][1:0]==i_response_tag[1:0])"),
    ("duplicate_response", "endpoint_tag_table", "&&r_sent[response_slot]&&!r_done[response_slot]&&", "&&r_sent[response_slot]&&1'b1&&"),
    ("completion_reselect", "endpoint_tag_table", "else if(!r_complete_valid&&done_found)", "else if(done_found)"),
    ("error_data_committed", "endpoint_tag_table", "o_complete_valid&&(r_status[r_complete_slot]==4'd0)", "o_complete_valid"),
    ("destination_ignored", "endpoint_tag_table", "(i_response_dst==i_local_id)&&", "1'b1&&"),
    ("reset_pending_preserved", "endpoint_read_originator", "r_pending<=1'b0;r_captured<=1'b0;r_port<=2'd0;", "r_pending<=r_pending;r_captured<=1'b0;r_port<=2'd0;"),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--shell-baseline", action="store_true")
    parser.add_argument("--faults", action="store_true", help="Check seven actual production RTL mutations")
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.label):
        parser.error("label must be a simple fresh directory name")
    if args.shell_baseline and args.faults:
        parser.error("old-shell red evidence and implemented RTL faults are separate stages")
    out = ROOT / "build/verification/endpoint_transaction" / args.label
    out.mkdir(parents=True, exist_ok=False)
    tools = {name: shutil.which(getattr(args, name)) for name in ("iverilog", "vvp")}
    if not all(tools.values()):
        raise SystemExit("Icarus missing: pass explicit --iverilog and --vvp")
    result = dict(shell_baseline=args.shell_baseline, cases=[], source_sha256={}, tools=tools, command=[sys.executable] + sys.argv, python_optimization=sys.flags.optimize)
    result["tool_versions"] = {}
    for name, path in tools.items():
        version = subprocess.run([path, "-V"], capture_output=True, text=True, timeout=10)
        result["tool_versions"][name] = (version.stdout + version.stderr).splitlines()[:2]
    result["source_sha256"][str(Path(__file__).resolve().relative_to(ROOT))] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    contract = ROOT / "config/endpoint_transaction_contract.json"
    result["source_sha256"][str(contract.relative_to(ROOT))] = hashlib.sha256(contract.read_bytes()).hexdigest()
    configurations = [(module, 1, None) for module in MODULES] if args.shell_baseline else [(f"ports{ports}", ports, None) for ports in (1, 2, 4)]
    if args.faults:
        configurations += [(fault[0], 1, fault) for fault in MUTATIONS]
    for name, ports, mutation in configurations:
        folder = out / name
        folder.mkdir()
        modules = (name,) if args.shell_baseline else MODULES + ("endpoint_read_encode",)
        for module in modules:
            source = ROOT / "rtl/endpoint" / f"{module}.v"
            text = source.read_text()
            result["source_sha256"][str(source.relative_to(ROOT))] = hashlib.sha256(source.read_bytes()).hexdigest()
            if mutation and module == mutation[1]:
                if text.count(mutation[2]) != 1:
                    raise RuntimeError(f"mutation must match one production expression: {name}")
                text = text.replace(mutation[2], mutation[3])
            (folder / source.name).write_text(text)
        (folder / "tb.sv").write_text(shell_tb(name) if args.shell_baseline else TB.replace("__PORTS__", str(ports)))
        commands = [[tools["iverilog"], "-g2012", "-Wall", "-s", "tb", "-o", "sim.vvp", "tb.sv"] + [f"{module}.v" for module in modules],
                    [tools["vvp"], "sim.vvp"]]
        compiled = subprocess.run(commands[0], cwd=folder, capture_output=True, text=True, timeout=60)
        (folder / "compile.log").write_text(compiled.stdout + compiled.stderr)
        if compiled.returncode:
            raise RuntimeError(f"compile failure is not functional evidence: {folder}")
        run = subprocess.run(commands[1], cwd=folder, capture_output=True, text=True, timeout=60)
        log = run.stdout + run.stderr
        (folder / "run.log").write_text(log)
        expected_failure = args.shell_baseline or mutation is not None
        passed = (run.returncode != 0 and "ORIGINATOR_SCOREBOARD" in log) if expected_failure else (run.returncode == 0 and f"PASS ports={ports}" in log)
        result["cases"].append(dict(name=name, ports=ports, commands=commands, returncode=run.returncode,
                                    expected_failure=expected_failure, passed=passed, output=log.strip()))
    result["passed"] = all(case["passed"] for case in result["cases"])
    result["artifact_sha256"] = {str(p.relative_to(out)): hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in sorted(out.rglob("*")) if p.is_file()}
    (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("passed", "shell_baseline", "cases")}, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

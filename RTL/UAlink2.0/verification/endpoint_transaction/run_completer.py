#!/usr/bin/env python3
"""Exercise the real four-slot read Completer with an independent memory BFM.

Run: python3 verification/endpoint_transaction/run_completer.py --label completer
Outputs: reports/endpoint_transaction/completer_<label>/summary.json, snapshots,
memory/vectors, tool commands and actual compile/runtime logs. Next: connect the
real receiver and tl_tx_prepared while retaining this unit's causal scoreboard.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import random
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
RTL = ROOT / "rtl/endpoint/endpoint_read_completer.v"
ENCODER = ROOT / "rtl/endpoint/endpoint_response_encode.v"

SHELL_TB = r'''module completer_shell_tb; // 仅通过已有壳的真实接口观察未实现服务。
wire ready,implemented; // 保存壳实际能力和请求接纳。
endpoint_read_completer dut(.i_clk(1'b0),.i_rstn(1'b1),.i_enable(1'b1),.i_valid(1'b1),.i_data(512'd0),.i_meta(128'd0),.o_ready(ready),.o_implemented(implemented)); // 发出真实有效服务请求。
initial begin #1; if(implemented!==1'b1) $fatal(1,"FAIL unimplemented_completer ready=%b",ready); $display("PASS implemented"); $finish; end // 不用接口不匹配的编译错误充当行为红测。
endmodule // 结束旧壳能力红测。
'''

TB = r'''`timescale 1ns/1ps // 固定本地同步事务测试时间单位。
module completer_tb; // 独立保存请求、内存事件和完整响应因果关系。
reg clk=0,rstn=0,rv=0,mready=0,mrv=0,captured=0; // 驱动各独立握手边界。
reg [9:0] local_id=10'h3a5,src=0,dst=10'h3a5; // 使用完整10位高值本地标识。
reg [10:0] tag=0; reg [56:0] address=0; // 保留完整Tag和地址高位。
reg [5:0] length=15; reg [7:0] attr=255,metadata=0; // 驱动本子集长度和访问属性。
reg [1:0] vc=0,asi=0,result_slot=0,accepted=0; // 驱动属性、slot与半Flit接纳数量。
reg pool=0; reg [511:0] result_data=0; reg [3:0] result_status=0; // 内存返回数据只能由BFM驱动。
wire rr,mvalid,mrready,sv,error; wire [1:0] mslot,dvalid; // 观察请求、内存和发送所有权。
wire [56:0] maddr; wire [5:0] mlen; wire [7:0] mattr,mmeta; wire [1:0] masi; // 观察完整内存命令。
wire [255:0] control; wire [511:0] data; wire [7:0] count; // 观察真实Control、两个Data半字和槽占用。
reg [10:0] tags[0:23]; reg [9:0] sources[0:23]; reg [56:0] addresses[0:23]; // 保存独立请求序列。
reg [255:0] expected_control[0:23]; reg [511:0] expected_data[0:23]; // Python独立字段/字节oracle，非被测编码器输出。
reg [3:0] expected_status[0:23]; reg [7:0] memory[0:4095]; // 独立字节数组内存及预期状态。
integer pending[0:3],due[0:3],slot_for[0:23]; // BFM跟踪实际已发slot及随机返回期限。
integer result_seen[0:23],header_seen[0:23],halves_seen[0:23]; // 独立因果、单次Header和Data完整性记账。
integer sent=0,issued=0,retired=0,cycles=0,seed=82731; // 真实握手推进计数。
integer total_requests=0,total_memory=0,total_results=0,total_responses=0; // 跨复位阶段保留已执行正常流量统计。
integer partial=0,double_accept=0,full_stalls=0,high_addresses=0,error_events=0,ooo=0,header_first=0,data_first=0,memory_stalls=0; // 保存关键覆盖分母的实际执行数。
integer p,t,n,fd,fields,chosen,return_id,return_kind,duplicate_slot=-1,invalid_status_done=0,duplicate_done=0; // 保存有限随机调度与故障注入状态。
integer expecting_error=0,tracking=0,limit,mem_slot_sample,mem_id_sample; // 控制独立合法阶段与定向错误检查。
reg [511:0] held_mem; reg [1:0] held_slot; reg mem_stalled=0; // 检查内存请求反压稳定性。
endpoint_read_completer dut(.i_clk(clk),.i_rstn(rstn),.i_local_id(local_id), // 实例化实际Completer和实际Response编码依赖。
 .i_request_valid(rv),.o_request_ready(rr),.i_request_tag(tag),.i_request_src(src),.i_request_dst(dst),.i_request_address(address), // 连接完整实际请求描述符。
 .i_request_length(length),.i_request_attr(attr),.i_request_vc(vc),.i_request_pool(pool),.i_request_asi(asi),.i_request_metadata(metadata), // 连接子集属性。
 .o_mem_valid(mvalid),.i_mem_ready(mready),.o_mem_slot(mslot),.o_mem_address(maddr),.o_mem_length(mlen),.o_mem_attr(mattr),.o_mem_asi(masi),.o_mem_metadata(mmeta), // 连接独立内存BFM请求。
 .i_mem_result_valid(mrv),.o_mem_result_ready(mrready),.i_mem_result_slot(result_slot),.i_mem_result_data(result_data),.i_mem_result_status(result_status), // 连接真实内存完成。
 .o_source_valid(sv),.o_source_control(control),.i_source_captured(captured),.o_data_valid(dvalid),.o_data(data),.i_data_accepted(accepted),.o_error(error),.o_count(count)); // 分别连接Header和Data所有权反馈。
// 每步检查当前边界后再执行时钟，参考不读取任何DUT内部状态。
task step; // 执行一个真实同步周期。
integer k,b; // 仅用于独立内存和计数检查。
begin // 开始实际周期。
 #2; // 等待当前组合接口稳定。
 if(rstn) begin // 正常周期检查明确期望的错误分类。
  if(tracking && (sv===1'b1 || dvalid!==2'd0) && (retired>=sent || !result_seen[retired])) $fatal(1,"FAIL response_before_memory_result id=%0d",retired); // 必须在本沿结果记账前已有真实已保存完成。
  if(error !== (expecting_error!=0)) $fatal(1,"FAIL diagnostic cycle=%0d got=%b expected=%0d",cycles,error,expecting_error); // full和等待不能误报错误，非法事件必须可见。
  if(mrv && !mrready) $fatal(1,"FAIL result_not_consumed"); // 已保留结果空间且非法返回也按冻结策略消费。
  if(error) error_events=error_events+1; // 保存被实际诊断的事件数。
  if(tracking) begin // 正常事务阶段记录独立请求到响应完整链条。
   if(mem_stalled && (!mvalid || mslot!==held_slot || {maddr,mlen,mattr,masi,mmeta}!==held_mem[80:0])) $fatal(1,"FAIL memory_hold"); // 检查被反压命令字段保持。
   mem_stalled=mvalid&&!mready; held_slot=mslot; held_mem={maddr,mlen,mattr,masi,mmeta}; // 保存下一周期内存保持预期。
   if(mvalid && mready) begin // 内存BFM只能由实际命令握手创建返回任务。
    if(issued>=sent) $fatal(1,"FAIL memory_without_request"); // 不允许尚未接收请求先执行。
    if(maddr!==addresses[issued] || mlen!==6'd15 || mattr!==8'hff || masi!==0 || mmeta!==0) $fatal(1,"FAIL memory_descriptor id=%0d got=%h expected=%h",issued,maddr,addresses[issued]); // 检查57位地址包括bit56以及所有属性。
    if(pending[mslot]>=0) $fatal(1,"FAIL duplicate_memory_issue"); // 一个在途slot不能被重复执行。
    pending[mslot]=issued; due[mslot]=cycles+2+($unsigned($random(seed))%13); slot_for[issued]=mslot; // 记录实际slot，独立选择内存完成延迟。
    if(maddr[56:32]!=0) high_addresses=high_addresses+1; // 统计真实传给BFM的高位地址。
    issued=issued+1; total_memory=total_memory+1; // 只有真实内存请求才推进执行数。
   end // 结束内存命令处理。
   if(mrv && mrready && return_kind==1) begin // 仅正常BFM结果更新独立完成账本。
    if(pending[result_slot]!=return_id || result_seen[return_id]) $fatal(1,"FAIL duplicate_or_unissued_result"); // 内存完成必须对应一个已发请求。
    for(k=0;k<return_id;k=k+1) if(!result_seen[k]) ooo=ooo+1; // 记录高序号先完成的实际乱序样本。
    result_seen[return_id]=1; pending[result_slot]=-1; duplicate_slot=result_slot; total_results=total_results+1; // 保存slot关联而不预造响应。
   end // 非法内存结果即使被消费也不得更新参考有效槽。
   if(sv || dvalid!=0) begin // 任何Response或Data都必须已有该队首的真实内存完成。
    if(retired>=sent || !result_seen[retired]) $fatal(1,"FAIL response_before_memory_result id=%0d",retired); // 拒绝未执行或用其他slot结果冒充完成。
    if(sv && (header_seen[retired] || control!==expected_control[retired])) $fatal(1,"FAIL response_control id=%0d got=%h expected=%h",retired,control,expected_control[retired]); // 检查完整Tag/ID/status和单次Header捕获。
    if(dvalid!=(2-halves_seen[retired])) $fatal(1,"FAIL data_count id=%0d",retired); // 每笔响应恰有两个半Flit。
    if(dvalid!=0 && data[255:0] !== expected_data[retired][256*halves_seen[retired] +:256]) $fatal(1,"FAIL data_low id=%0d halves=%0d",retired,halves_seen[retired]); // 首个可接受半字必须是仍未入队的部分。
    if(dvalid==2 && data[511:256]!==expected_data[retired][511:256]) $fatal(1,"FAIL data_high id=%0d",retired); // 显式验证全部上半256位。
   end // 结束当前队首输出对照。
   if(captured && halves_seen[retired]==0 && accepted==0) header_first=header_first+1; // 实际观察Header先于Data所有权转移。
   if(accepted!=0 && !header_seen[retired] && !captured) data_first=data_first+1; // 实际观察Data先于Header所有权转移。
   if(mvalid && !mready) memory_stalls=memory_stalls+1; // 记录真实内存命令反压。
   if(captured) header_seen[retired]=1; // Header捕获仅转移Header所有权。
   if(accepted==1) partial=partial+1; if(accepted==2) double_accept=double_accept+1; // 分别计数部分与整对Data接纳。
   halves_seen[retired]=halves_seen[retired]+accepted; // 只推进实际接纳的半字数量。
   if(retired<sent && header_seen[retired] && halves_seen[retired]==2) begin retired=retired+1; total_responses=total_responses+1; end // 两类所有权都转移才退休。
   if(rv && rr) begin sent=sent+1; total_requests=total_requests+1; end // 单独保存新请求的实际接纳。
   if(rv && !rr && count==4) full_stalls=full_stalls+1; // 明确观察四槽满后的背压。
  end // 结束正常流量参考检查。
 end // 结束非复位检查。
 clk=1; #2; clk=0; cycles=cycles+1; // 执行真实同步寄存器更新。
 if(tracking && rstn && count!=(sent-retired)) $fatal(1,"FAIL slot_lifetime count=%0d expected=%0d",count,sent-retired); // 提前按Header释放或遗失Data会破坏容量守恒。
end // 结束完整测试周期。
endtask // 结束独立step辅助。
// BFM按实际内存请求slot调度，按字节数组构造数据，不调用Response编码器。
task run_batch; // 执行有限并发请求、乱序内存返回和独立发送反压。
input integer batch_limit; // 限定本阶段请求数量。
integer loop_count,k,b,start_cycle; // 保存有限调度边界和字节索引。
begin // 开始一次正常事务批次。
 sent=0; issued=0; retired=0; tracking=1; duplicate_slot=-1; duplicate_done=0; invalid_status_done=0; mem_stalled=0; start_cycle=cycles; // 清空本批参考状态。
 for(k=0;k<4;k=k+1) pending[k]=-1; // 所有BFM slot开始为空。
 for(k=0;k<24;k=k+1) begin result_seen[k]=0; header_seen[k]=0; halves_seen[k]=0; end // 独立清空每个事务阶段记录。
 for(loop_count=0;loop_count<1200 && retired<batch_limit;loop_count=loop_count+1) begin // 设置有限上界拒绝永久阻塞。
  rv=(sent<batch_limit); tag=tags[sent%24]; src=sources[sent%24]; address=addresses[sent%24]; // 未接纳源继续保持同一个请求。
  mready=(loop_count>=12)&&(($unsigned($random(seed))%4)!=0); // 先填满四槽，再随机延迟内存接纳。
  mrv=0; expecting_error=0; return_kind=0; chosen=-1; // 默认没有任何内存完成或注错。
  for(k=3;k>=0;k=k-1) if(pending[k]>=0 && due[k]<=cycles && chosen<0) chosen=k; // 优先高slot以激励真实乱序完成。
  if(loop_count==6) begin mrv=1;result_slot=0;result_status=0;return_kind=2;expecting_error=1; end // 四槽已分配但未执行时注入非法完成。
  else if(chosen>=0 && !invalid_status_done) begin mrv=1;result_slot=chosen;result_status=4'hf;return_kind=2;expecting_error=1;invalid_status_done=1; end // 非法状态不得覆盖已预留的有效结果。
  else if(duplicate_slot>=0 && !duplicate_done) begin mrv=1;result_slot=duplicate_slot;result_status=0;result_data={512{1'b1}};return_kind=2;expecting_error=1;duplicate_done=1; end // 已完成但未退休slot的重复结果必须诊断。
  else if(chosen>=0) begin // 只有BFM存在真实已发任务才生成正常返回。
   mrv=1;result_slot=chosen;return_id=pending[chosen];return_kind=1;result_data=0;result_status=3; // 默认为4KiB测试映射外的完整错误beat。
   if(addresses[return_id]<4096) begin // 只由BFM定义测试内存范围，生产模块不能截断地址。
    result_status=0; for(b=0;b<64;b=b+1) result_data[b*8 +:8]=memory[addresses[return_id]+b]; // 从独立字节数组返回自然低字节在低位的完整512位。
   end // 结束实际内存地址服务。
  end // 结束正常BFM返回选择。
  #1; captured=sv && loop_count>=80 && (($unsigned($random(seed))%4)!=0); // Header可独立长期反压，先让部分Data入队。
  accepted=0; // 默认不消费任何Data。
  if(loop_count>=60 && dvalid!=0 && !(retired%3==1 && !header_seen[retired])) begin // 部分事务Data先行，另一部分Header先行。
   accepted=$unsigned($random(seed))%3; if(accepted>dvalid) accepted=dvalid; // 只反馈真实可接纳的零至两个半字。
   if(retired%3==0 && halves_seen[retired]==0) accepted=1; // 定向验证部分接纳后的高半前移。
  end // 结束独立Data队列接纳控制。
  step(); // 对所有本周期真实边界执行检查和时钟更新。
 end // 结束有界随机批次。
 rv=0;mrv=0;captured=0;accepted=0;expecting_error=0;step(); // 解除全部输入并核实不会重复回应。
 if(retired!=batch_limit || issued!=batch_limit || count!=0) $fatal(1,"FAIL batch_drain retired=%0d issued=%0d count=%0d",retired,issued,count); // 有限停顿后必须完整排空。
 tracking=0; // 结束本批正常事务参考。
end // 结束run_batch流程。
endtask // 结束独立BFM批次辅助。
initial begin // 准備明确的请求向量和字节内存，先测非法因果事件。
 $readmemh("memory.hex",memory); fd=$fopen("requests.txt","r"); // 读取独立生成的BFM字节和请求oracle。
 for(n=0;n<24;n=n+1) begin fields=$fscanf(fd,"%h %h %h %h %h %h\n",tags[n],sources[n],addresses[n],expected_control[n],expected_data[n],expected_status[n]); if(fields!=6) $fatal(1,"FAIL request_vectors"); end // 预期不调用真实编码器或状态机。
 $fclose(fd);step();rstn=1; // 同步复位后开始明确错误事件。
 mrv=1;result_slot=3;result_status=0;expecting_error=1;step(); // 空表收到未知slot不能产生Response。
 mrv=0;captured=1;step();captured=0;accepted=3;step();accepted=0; // 无有效发送时的反馈不得推进槽。
 rv=1;dst=local_id^1;step();dst=local_id;address=1;step();address=0;length=14;step();length=15;attr=0;step();attr=255;vc=1;step();vc=0;pool=1;step();pool=0;asi=1;step();asi=0;metadata=1;step();metadata=0;rv=0;expecting_error=0; // 分别拒绝非法dst与每个本地profile字段。
 if(count!=0 || mvalid || sv || dvalid) $fatal(1,"FAIL invalid_created_work"); // 非法请求和虚假完成不能创建任何工作。
 run_batch(24); // 执行四槽并发、真实内存完成和两个Data半字转移。
 rv=1;tag=11'h7ff;src=10'h3ff;address=64;mready=0;step();rv=0; // 额外分配一个稍后被复位中止的真实请求。
 #1;mem_slot_sample=mslot;mready=1;step();mready=0; // 先发生真实内存请求。
 mrv=1;result_slot=mem_slot_sample;result_data=512'hfedcba9876543210;result_status=0;step();mrv=0; // 保存真实结果但不让Header或Data被接纳。
 if(!sv || dvalid!=2 || count!=1) $fatal(1,"FAIL reset_setup"); // 确认复位确实打断一个持有完整结果的槽。
 rstn=0;step();rstn=1; // 同步复位清除描述符和结果有效位。
 if(count!=0 || mvalid || sv || dvalid) $fatal(1,"FAIL reset_validity"); // 旧Header/Data不能越过复位。
 mrv=1;result_slot=mem_slot_sample;expecting_error=1;step();mrv=0;expecting_error=0; // 重用前的迟到旧slot完成应作为未知事件消费诊断。
 run_batch(8); // 再次真实读写服务，检查复位后槽可复用。
 if(total_requests!=32 || total_memory!=32 || total_results!=32 || total_responses!=32 || partial==0 || double_accept==0 || full_stalls==0 || high_addresses==0 || ooo==0 || header_first==0 || data_first==0 || memory_stalls==0) $fatal(1,"FAIL coverage"); // 要求全部因果链与关键边界实际覆盖。
 $display("PASS requests=%0d memory=%0d results=%0d responses=%0d partial=%0d double=%0d full_stalls=%0d high_addresses=%0d errors=%0d out_of_order=%0d header_first=%0d data_first=%0d memory_stalls=%0d cycles=%0d",total_requests,total_memory,total_results,total_responses,partial,double_accept,full_stalls,high_addresses,error_events,ooo,header_first,data_first,memory_stalls,cycles); // 输出可审计的实际执行计数。
 $finish; // 正常完成所有有界自校验。
end // 结束完整Completer自校验。
endmodule // 结束completer_tb。
'''

def vectors(directory: Path) -> None:
    memory = bytes((i * 37 + (i >> 2) * 13 + (i >> 7) * 29 + 91) & 255 for i in range(4096))
    (directory / "memory.hex").write_text("".join(f"{byte:02x}\n" for byte in memory))
    rng = random.Random(61039)
    addresses = [0, 64, 4032, 4096, 1 << 56, (1 << 56) | 64, 1 << 32, 384]
    tags = [0, 1, 1023, 2047, 1024, 1535]
    rows = []
    for index in range(24):
        addr = addresses[index % 8] if index < 16 else rng.randrange(64) * 64
        tag = tags[index % 6]
        src = [0, 1023, 512, 511, 1, 997][index % 6]
        status = 0 if addr < len(memory) else 3
        value = int.from_bytes(memory[addr:addr + 64], "little") if not status else 0
        field = (2 << 60) | (tag << 47) | (status << 38) | (1 << 37) | (1 << 36) | (0x3A5 << 26) | (src << 16)
        rows.append(f"{tag:x} {src:x} {addr:x} {field:064x} {value:0128x} {status:x}\n")
    (directory / "requests.txt").write_text("".join(rows))

def execute(command: list[str], directory: Path, name: str) -> dict:
    start = time.monotonic()
    with (directory / f"{name}.log").open("w") as log:
        try:
            result = subprocess.run(command, cwd=directory, stdout=log, stderr=subprocess.STDOUT, timeout=120, check=False)
            record = {"command": command, "returncode": result.returncode, "timeout": False}
        except subprocess.TimeoutExpired:
            record = {"command": command, "returncode": None, "timeout": True}
    record["seconds"] = round(time.monotonic() - start, 3)
    (directory / f"{name}.json").write_text(json.dumps(record, indent=2) + "\n")
    return record

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--label", required=True)
    parser.add_argument("--mode", choices=("functional", "shell"), default="functional")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.label): parser.error("choose a safe new label")
    compiler, runtime = shutil.which("iverilog"), shutil.which("vvp")
    if not compiler or not runtime: parser.error("iverilog and vvp are required")
    output = ROOT / "reports/endpoint_transaction" / f"completer_{args.label}"
    if output.exists(): parser.error(f"evidence exists; choose a new label: {output}")
    output.mkdir(parents=True)
    original = RTL.read_text()
    (output / "source.v").write_text(original)
    (output / "testbench.sv").write_text(SHELL_TB if args.mode == "shell" else TB)
    shutil.copyfile(ENCODER, output / ENCODER.name)
    shutil.copyfile(__file__, output / "run_completer.py")
    execute([compiler, "-V"], output, "iverilog_version")
    summary = {"scope": "single64B ordinary Read four-slot Completer, not full Endpoint", "mode": args.mode,
               "source_sha256": hashlib.sha256(RTL.read_bytes()).hexdigest(), "encoder_sha256": hashlib.sha256(ENCODER.read_bytes()).hexdigest(), "cases": []}
    mutations = {
        "address_msb": ("assign o_mem_address = address_q[issue_q];", "assign o_mem_address = {1'b0,address_q[issue_q][55:0]};"),
        "early_response": ("busy_q[head_q] && complete_q[head_q]", "busy_q[head_q] && issued_q[head_q]"),
        "upper_data": ("result_q[head_q][511:256]", "(result_q[head_q][511:256] ^ 256'h1)"),
    }
    cases = [None] if args.mode == "shell" else [None, *mutations]
    for mutation in cases:
        directory = output / (mutation or "normal")
        directory.mkdir()
        text = original
        record = {"mutation": mutation}
        if mutation:
            before, after = mutations[mutation]
            if before not in text: parser.error(f"mutation anchor missing: {mutation}")
            text = text.replace(before, after)
            record["mutation_change"] = {"before": before, "after": after}
        (directory / "dut.v").write_text(text)
        if args.mode == "functional": vectors(directory)
        top = "completer_shell_tb" if args.mode == "shell" else "completer_tb"
        record["compile"] = execute([compiler, "-g2012", "-Wall", "-s", top, "-o", "simulation.vvp", str(output / "testbench.sv"), "dut.v", str(output / ENCODER.name)], directory, "compile")
        record["status"] = "compile_failed"
        if record["compile"]["returncode"] == 0:
            record["simulation"] = execute([runtime, "simulation.vvp"], directory, "simulation")
            log = (directory / "simulation.log").read_text(); code = record["simulation"]["returncode"]
            if mutation:
                record["status"] = "detected" if code is not None and code > 0 and re.search(r"FAIL (memory_descriptor|response_before_memory_result|data_low|data_high|slot_lifetime)", log) and "PASS" not in log else "mutation_missed"
            else:
                record["status"] = "pass" if code == 0 and "PASS" in log and "FAIL" not in log else "failed"
                record["coverage"] = {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", log)}
        (directory / "result.json").write_text(json.dumps(record, indent=2) + "\n")
        summary["cases"].append(record); print(record["status"], mutation, flush=True)
    summary["status"] = "pass" if all(c["status"] in ("pass", "detected") for c in summary["cases"]) else "fail"
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(summary["status"], output / "summary.json")
    return 0 if summary["status"] == "pass" else 1

if __name__ == "__main__": sys.exit(main())

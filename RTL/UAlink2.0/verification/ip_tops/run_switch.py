#!/usr/bin/env python3
"""Check the internal packet Switch top using real Icarus/VVP executions.

Run: python3 verification/ip_tops/run_switch.py --label switch_initial
Outputs: reports/ip_tops/switch_<label>/{summary.json,*/compile.log,*/simulation.log}
Next: connect the Endpoint 544-bit output and retain separate full-Switch gaps.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
RTL = ROOT / "rtl/switch/ualink_switch_top.v"
SUPPORT = sorted(p for p in (ROOT / "rtl").rglob("*.v") if p != RTL)

TB = r'''`timescale 1ns/1ps // 定义同步数字测试时间单位。
module switch_tb; // 独立检查多端口路由、握手与包所有权。
parameter PORTS=4, WIDTH=544; // 从编译参数选择实际被测端口数量和字宽。
reg clk=0, rstn=0; // 驱动同一时钟和同步低有效复位。
reg [PORTS*10-1:0] routes=0, dst=0; // 保存静态路由配置和每输入目标。
reg [PORTS-1:0] enable=0, iv=0, il=0, ore=0; // 驱动端口使能、输入有效和输出反压。
reg [PORTS*WIDTH-1:0] id=0; // 每个源保持自己尚未握手的数据。
wire [PORTS-1:0] ir, ov, ol, err; // 观察输入握手、输出和拒绝标志。
wire [PORTS*WIDTH-1:0] od; // 观察完整输出数据而不截断高位。
integer seq[0:PORTS-1], left[0:PORTS-1], owner[0:PORTS-1], grants[0:PORTS-1]; // 跟踪源序号、多beat包和独立所有权约束。
integer wait_age[0:PORTS-1], last_accept[0:PORTS-1]; // 保存公平性和逐源数据顺序证据。
reg [PORTS-1:0] prev_stall=0, prev_last=0; // 保存前一拍需要保持的输出状态。
reg [PORTS*WIDTH-1:0] prev_data=0; // 保存完整被反压的数据字。
integer cycles=0, deliveries=0, stalls=0, packets=0, errors=0, resets=0, fair_cycles=0; // 累计真实检查执行次数。
integer phase=0, p, e, t, accepted, seed; // 保存测试和参考扫描变量。
integer initial_deliveries, before_reset, total_left; // 记录阶段进展并拒绝零流量通过。
ualink_switch_top #(.PORTS(PORTS),.DATA_WIDTH(WIDTH)) dut ( // 实例化真正Switch顶层源码。
 .clk(clk),.rstn(rstn),.i_route_ids(routes),.i_port_enable(enable), // 连接时钟和静态路由配置。
 .i_valid(iv),.o_ready(ir),.i_data(id),.i_dst(dst),.i_last(il), // 连接各输入流。
 .o_valid(ov),.i_ready(ore),.o_data(od),.o_last(ol),.o_route_error(err) // 连接各输出流和可见错误。
); // 结束被测模块实例。
// 新beat生成只负责刺激，不计算任何仲裁预期。
task offer; // 给一个源生成带独立源标识和序号的完整新beat。
 input integer port, destination, is_last; // 指定源、逻辑目标和包结束位置。
 integer bit_index; // 遍历完整数据字生成独立随机高位。
 begin // 开始一个源的新beat刺激。
  for(bit_index=0;bit_index<WIDTH;bit_index=bit_index+1) id[port*WIDTH+bit_index]=$random(seed); // 全宽随机数据用于发现任意位路由错误。
  id[port*WIDTH +: 32]=(port<<24)|seq[port]; seq[port]=seq[port]+1; // 嵌入只用于识别源与顺序的低位标签。
  dst[port*10 +:10]=destination; il[port]=is_last; iv[port]=1; // 在握手前保持该源的目标、末拍和数据。
 end // 结束新beat刺激生成。
endtask // 结束offer刺激辅助。
// 参考只扫描唯一目标、比较完整输入输出，并检查守恒；不重演轮询选择算法。
task step; // 检查一个周期并施加实际时钟上升沿。
 integer ii, ee, ss, nn, mm, one, count_in, count_out; // 为本次逻辑观察保存独立局部索引。
 begin // 开始周期检查。
  #2; // 等待组合路由稳定后采样实际握手。
  if(rstn) begin // 正常工作时检查外部语义。
   count_in=0; count_out=0; // 清空此拍握手守恒计数。
   for(ii=0;ii<PORTS;ii=ii+1) begin // 根据静态配置独立查找每个输入的目的。
    nn=0; mm=-1; // 初始没有任何目的匹配。
    for(ee=0;ee<PORTS;ee=ee+1) if(enable[ee] && routes[ee*10 +:10]==dst[ii*10 +:10]) begin nn=nn+1; mm=ee; end // 仅接受唯一enabled逻辑目标。
    if(err[ii] !== (iv[ii] && nn!=1)) $fatal(1,"FAIL route_error cycle=%0d source=%0d",cycles,ii); // 无匹配或重复匹配必须可见拒绝。
    if(iv[ii] && nn!=1 && ir[ii]) $fatal(1,"FAIL invalid_route_accepted"); // 错误目标不能握手丢包。
    one=0; // 统计同一源的实际输出握手数。
    for(ee=0;ee<PORTS;ee=ee+1) if(ov[ee] && ore[ee] && od[ee*WIDTH+24 +:8]==ii) one=one+1; // 独立检查一个输入最多发送到一个输出。
    if(one !== (iv[ii] && ir[ii])) $fatal(1,"FAIL conservation source=%0d outputs=%0d ready=%b",ii,one,ir[ii]); // 双向握手必须一一对应。
    if(iv[ii] && ir[ii]) count_in=count_in+1; // 累计真实输入接收。
   end // 结束输入路由与守恒检查。
   for(ee=0;ee<PORTS;ee=ee+1) begin // 比较每个实际输出的完整数据和包序列。
    if(prev_stall[ee]) begin // 已经有效且被反压的输出必须保持。
     if(ov[ee]!==1'b1 || od[ee*WIDTH +:WIDTH]!==prev_data[ee*WIDTH +:WIDTH] || ol[ee]!==prev_last[ee]) $fatal(1,"FAIL hold cycle=%0d egress=%0d",cycles,ee); // 新竞争者不能替换被反压beat。
     stalls=stalls+1; // 记录真实保持检查。
    end // 结束反压稳定性检查。
    if(ov[ee]) begin // 有效输出必须来自一个合法且仍有效的源。
     ss=od[ee*WIDTH+24 +:8]; // 只以刺激标签识别源，不查看被测内部仲裁状态。
     if(ss<0 || ss>=PORTS) $fatal(1,"FAIL corrupt_source_tag"); // 拒绝任意数据破坏导致的非法源。
     if(!iv[ss] || od[ee*WIDTH +:WIDTH]!==id[ss*WIDTH +:WIDTH] || ol[ee]!==il[ss]) $fatal(1,"FAIL data cycle=%0d egress=%0d source=%0d",cycles,ee,ss); // 完整字与last必须对应未握手源beat。
     if(!enable[ee] || routes[ee*10 +:10]!==dst[ss*10 +:10] || err[ss]) $fatal(1,"FAIL routing cycle=%0d egress=%0d source=%0d",cycles,ee,ss); // 输出必须是唯一enabled目的。
     if(owner[ee]>=0 && owner[ee]!=ss) $fatal(1,"FAIL packet_owner cycle=%0d egress=%0d",cycles,ee); // 包内和首次停顿期间不允许换源。
     owner[ee]=ss; // 从实际首次选择建立参考所有权约束。
     if(ore[ee]) begin // 有效输出握手后推进独立记账。
      if((od[ee*WIDTH +:24])<=last_accept[ss]) $fatal(1,"FAIL source_order"); // 每源接收序号必须严格递增。
      last_accept[ss]=od[ee*WIDTH +:24]; grants[ss]=grants[ss]+1; // 记录顺序和公平服务次数。
      count_out=count_out+1; deliveries=deliveries+1; // 累计真实送达而非观察到valid。
      if(ol[ee]) begin owner[ee]=-1; packets=packets+1; end // 仅最后一拍握手后释放包所有权。
     end // 结束有效输出握手处理。
    end // 结束该输出的数据路由比较。
   end // 结束全部输出检查。
   if(count_in!=count_out) $fatal(1,"FAIL total_conservation"); // 每周期总接收和总送达完全相等。
   if(phase==3) begin // 连续单拍争用且目的持续ready时检查有界公平性。
    fair_cycles=fair_cycles+1; // 统计受公平条件约束的实际周期。
    if(count_out!=1) $fatal(1,"FAIL fairness_progress"); // 持续请求不能全部饿死。
    for(ii=0;ii<PORTS;ii=ii+1) begin // 逐源约束最大等待时间而不预测仲裁次序。
     if(ir[ii]) wait_age[ii]=0; else wait_age[ii]=wait_age[ii]+1; // 已服务清零，持续请求累计等待。
     if(wait_age[ii]>=PORTS) $fatal(1,"FAIL fairness source=%0d age=%0d",ii,wait_age[ii]); // 单拍持续争用必须在PORTS周期内服务。
    end // 结束公平等待界检查。
   end // 结束公平性阶段检查。
   errors=errors+$countones(err); // 记录无效路由拒绝样本数。
   prev_stall=ov & ~ore; prev_data=od; prev_last=ol; // 保存下次需要保持的完整beat。
  end else begin // 同步复位丢弃先前包所有权，不把复位当成正常交付。
   prev_stall=0; resets=resets+1; // 复位后重新开始稳定性检查。
   for(ee=0;ee<PORTS;ee=ee+1) owner[ee]=-1; // 清除参考包绑定。
  end // 结束复位与正常检查分支。
  clk=1; #2; clk=0; cycles=cycles+1; // 执行同步状态更新并回到低电平。
 end // 结束一个实际测试周期。
endtask // 结束step参考检查辅助。
initial begin // 依次执行有界定向阶段和随机多包阶段。
 seed=19073+PORTS; // 固定可重放的各端口配置随机种子。
 for(p=0;p<PORTS;p=p+1) begin seq[p]=1; left[p]=0; owner[p]=-1; grants[p]=0; wait_age[p]=0; last_accept[p]=0; routes[p*10 +:10]=100+p*7; end // 使用非连续route ID避免端口编号伪路由。
 enable={PORTS{1'b1}}; step(); rstn=1; // 同步复位后启用全部目的端口。
 phase=1; offer(PORTS-1,100,1); ore=0; step(); // 首次未握手选择高编号源。
 for(p=0;p<PORTS-1;p=p+1) offer(p,100,1); // 停顿期间加入低编号竞争者。
 repeat(5) step(); ore=1; // 保持五拍后只开放目标零。
 for(t=0;t<PORTS+2;t=t+1) begin #1; accepted=ir & iv; step(); iv=iv & ~accepted; end // 收完所有一拍请求并检查停顿后选择。
 if(deliveries!=PORTS) $fatal(1,"FAIL directed_delivery count=%0d",deliveries); // 定向阶段要求所有源真实送达。
 iv=0; ore={PORTS{1'b1}}; // 单独检查所有端口同时self-route而不争用。
 for(p=0;p<PORTS;p=p+1) offer(p,100+p*7,1); // 每源指向自身的配置ID。
 before_reset=deliveries; step(); iv=0; // 同一周期接收全部独立目的。
 if(deliveries!=before_reset+PORTS) $fatal(1,"FAIL self_route_parallel"); // 自路由及独立目的必须同时进展。
 iv=0; rstn=0; step(); rstn=1; // 为独立公平性阶段重新初始化轮询状态。
 phase=3; ore={PORTS{1'b1}}; // 持续开放全部输出，只在目标零争用。
 for(p=0;p<PORTS;p=p+1) offer(p,100,1); // 每源持续提供单拍包。
 for(t=0;t<PORTS*24;t=t+1) begin #1; accepted=ir & iv; step(); for(p=0;p<PORTS;p=p+1) if(accepted & (1<<p)) offer(p,100,1); end // 已握手源立即补充下一包，持续检查公平界。
 phase=4; iv=0; rstn=0; step(); // 在复位期间配置重复目标和禁用目的。
 enable[PORTS-1]=0; rstn=1; ore={PORTS{1'b1}}; // 第零ID重复匹配，最后端口不匹配。
 for(p=0;p<PORTS;p=p+1) offer(p,999,1); // 所有源先指向不存在的ID。
 repeat(3) step(); // 无效路由必须一直拒绝而不消失。
 for(p=0;p<PORTS;p=p+1) dst[p*10 +:10]=100+7*(PORTS-1); // 指向表中存在但明确禁用的目的。
 repeat(3) step(); // 禁用匹配同样必须拒绝而不丢包。
 rstn=0; step(); routes[10 +:10]=100; enable={PORTS{1'b1}}; rstn=1; // 复位期间把前两项改成重复enabled目标。
 for(p=0;p<PORTS;p=p+1) dst[p*10 +:10]=100; // 改为显式重复enabled目标。
 repeat(3) step(); // 检查重复ID无法静默选一个目的。
 iv=0; rstn=0; step(); // 重建正常路由并同步清除错误阶段输入。
 for(p=0;p<PORTS;p=p+1) routes[p*10 +:10]=100+p*7; enable={PORTS{1'b1}}; rstn=1; // 正常工作期间固定唯一目的配置。
 phase=5; initial_deliveries=deliveries; // 随机多beat与反压阶段独立计数。
 for(p=0;p<PORTS;p=p+1) begin left[p]=1+p; offer(p,100,left[p]==1); end // 所有源先用不同长度包争用目标零。
 for(t=0;t<1200;t=t+1) begin // 广泛检查多包交织、独立输出和中间beat停顿。
  for(e=0;e<PORTS;e=e+1) ore[e]=($random(seed)&3)!=0; // 随机目的反压。
  #1; accepted=ir & iv; step(); // 采样实际接收后执行检查与时钟更新。
  for(p=0;p<PORTS;p=p+1) begin // 每源只在握手后推进自己的流。
   if(accepted & (1<<p)) begin iv[p]=0; left[p]=left[p]-1; end // 已接收beat不再重放。
   if(!iv[p] && (($random(seed)&3)!=0)) begin // 空闲源可插入气泡再发下一个beat。
    if(left[p]==0) begin left[p]=1+($unsigned($random(seed))%4); dst[p*10 +:10]=100+7*($unsigned($random(seed))%PORTS); end // 只在包边界更改目的并允许self-route。
    offer(p,dst[p*10 +:10],left[p]==1); // 包内始终保持原目的和独立序号。
   end // 结束该源的新beat生成。
  end // 结束全部源推进。
 end // 完成随机数据阶段。
 ore={PORTS{1'b1}}; // 最后停止新包并解除全部反压。
 for(t=0;t<PORTS*12;t=t+1) begin // 有界排空剩余多beat包。
  #1; accepted=ir & iv; step(); // 检查每个真实排空操作。
  for(p=0;p<PORTS;p=p+1) begin // 仅继续已经开始的包。
   if(accepted & (1<<p)) begin iv[p]=0; left[p]=left[p]-1; end // 递减排空中的剩余beat数。
   if(!iv[p] && left[p]>0) offer(p,dst[p*10 +:10],left[p]==1); // 补充同一包尚未发送的beat。
  end // 完成排空源更新。
 end // 结束有界排空。
 total_left=0; for(p=0;p<PORTS;p=p+1) total_left=total_left+left[p]; // 汇总尚未送达的请求。
 if(iv!=0 || total_left!=0 || deliveries-initial_deliveries<100) $fatal(1,"FAIL drain_or_progress"); // 不允许以堵塞或零流量结束测试。
 phase=6; ore=0; offer(PORTS-1,100,0); step(); // 在未完成包和反压状态下准备复位。
 rstn=0; iv=0; step(); rstn=1; ore={PORTS{1'b1}}; offer(0,100,1); // 复位取消旧包所有权并允许新源接管。
 before_reset=deliveries; step(); iv=0; step(); // 观察新的包是否立即送达。
 if(deliveries!=before_reset+1) $fatal(1,"FAIL reset_owner"); // 旧owner不能跨复位堵塞新包。
 if(stalls<5 || errors<PORTS*6 || packets<50 || fair_cycles!=PORTS*24) $fatal(1,"FAIL coverage"); // 要求关键行为真实出现。
 $display("PASS ports=%0d width=%0d cycles=%0d deliveries=%0d packets=%0d stalls=%0d errors=%0d resets=%0d fairness_cycles=%0d",PORTS,WIDTH,cycles,deliveries,packets,stalls,errors,resets,fair_cycles); // 输出实际覆盖计数。
 $finish; // 正常返回真实仿真通过。
end // 结束全部测试阶段。
initial begin #100000; $fatal(1,"FAIL timeout"); end // 防止测试挂死伪装通过。
endmodule // 结束独立Switch测试台。
'''


def execute(cmd: list[str], directory: Path, name: str) -> dict:
    start = time.monotonic()
    with (directory / f"{name}.log").open("w") as log:
        try:
            result = subprocess.run(cmd, cwd=directory, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=120, check=False)
            record = {"command": cmd, "returncode": result.returncode, "timeout": False}
        except subprocess.TimeoutExpired:
            record = {"command": cmd, "returncode": None, "timeout": True}
    record["seconds"] = round(time.monotonic() - start, 3)
    (directory / f"{name}.json").write_text(json.dumps(record, indent=2) + "\n")
    return record


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--label", required=True)
    parser.add_argument("--rtl", type=Path, default=RTL, help="Explicit source override for retained RED evidence")
    parser.add_argument("--ports", type=int, nargs="+", default=[2, 3, 4])
    parser.add_argument("--width", type=int, default=544)
    parser.add_argument("--no-mutations", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.label):
        parser.error("use a safe new evidence label")
    if any(p < 2 or p > 16 for p in args.ports) or args.width < 32:
        parser.error("testbench supports 2..16 ports and width >=32")
    source = args.rtl.resolve()
    if not source.is_file():
        parser.error(f"missing RTL: {source}")
    compiler, runtime = shutil.which("iverilog"), shutil.which("vvp")
    if not compiler or not runtime:
        parser.error("iverilog and vvp are required")
    output = ROOT / "reports/ip_tops" / f"switch_{args.label}"
    if output.exists():
        parser.error(f"evidence exists, select a new label: {output}")
    output.mkdir(parents=True)
    (output / "switch_tb.sv").write_text(TB)
    shutil.copyfile(source, output / "ualink_switch_top.v")
    shutil.copyfile(__file__, output / "run_switch.py")
    execute([compiler, "-V"], output, "iverilog_version")
    summary = {"scope": "internal digital packet fabric, not complete UALink Switch",
               "source": str(source), "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
               "cases": [], "status": "running"}
    summary["support_sources"] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in SUPPORT}
    configs = [(p, None) for p in dict.fromkeys(args.ports)]
    if not args.no_mutations:
        configs += [(4, "routing"), (4, "hold")]
    mutations = {
        "routing": (".i_dst(i_dst)", ".i_dst({(PORTS*10){1'b0}})"),
        "hold": ("if (locked_q[egress]) begin", "if (1'b0) begin"),
    }
    for ports, mutation in configs:
        directory = output / (f"ports{ports}" + (f"_{mutation}" if mutation else ""))
        directory.mkdir()
        text = source.read_text()
        record = {"ports": ports, "width": args.width, "mutation": mutation}
        if mutation:
            before, after = mutations[mutation]
            if text.count(before) != 1:
                record.update(status="mutation_anchor_error")
                summary["cases"].append(record)
                continue
            text = text.replace(before, after)
            record["mutation_change"] = {"before": before, "after": after}
        (directory / "dut.v").write_text(text)
        record["compile"] = execute([compiler, "-g2012", "-Wall", "-s", "switch_tb",
                                     f"-Pswitch_tb.PORTS={ports}", f"-Pswitch_tb.WIDTH={args.width}",
                                     "-o", "simulation.vvp", str(output / "switch_tb.sv"), "dut.v", *map(str, SUPPORT)],
                                    directory, "compile")
        record["status"] = "compile_failed"
        if record["compile"]["returncode"] == 0:
            record["simulation"] = execute([runtime, "simulation.vvp"], directory, "simulation")
            log = (directory / "simulation.log").read_text()
            code = record["simulation"]["returncode"]
            if mutation:
                detected = code is not None and code > 0 and bool(re.search(r"FAIL (route_error|invalid_route_accepted|conservation|hold|data|routing|packet_owner|source_order|fairness)", log)) and "PASS" not in log
                record["status"] = "detected" if detected else "mutation_missed"
            else:
                record["status"] = "pass" if code == 0 and "PASS " in log and "FAIL" not in log else "failed"
                record["coverage"] = {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", log)}
        (directory / "result.json").write_text(json.dumps(record, indent=2) + "\n")
        summary["cases"].append(record)
        (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(f"{record['status']}: ports={ports} mutation={mutation}", flush=True)
    summary["status"] = "pass" if all(c["status"] in ("pass", "detected") for c in summary["cases"]) else "fail"
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"{summary['status']}: {output / 'summary.json'}")
    return 0 if summary["status"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())

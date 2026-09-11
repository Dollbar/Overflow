"""Run python3 verification/tl_publish/run_receiver.py. Real publisher -> frozen tl_credit_port.
Writes actual initial FC and completion reception plus paid CMD/credit-return loop.
Retirement inputs here are a test model; actual FIFO integration is the next gate.
"""
from pathlib import Path
import json,subprocess,hashlib
R=Path(__file__).resolve().parents[2];D=R;S=R/'build/verification/tl_publish';S.mkdir(parents=True,exist_ok=True)
sources=[R/'rtl/tl/tl_credit_publish.v',*[p for p in sorted((R/'rtl/tl').glob('*.v')) if p.name not in ('tl_credit_publish.v','tl_receive_storage.v','tl_receive_context.v')]];rows=[]
cap=[i+9 if i<10 else i*3+1 for i in range(20)];capword=sum(x<<(8*i) for i,x in enumerate(cap))
for width in (8,16):
 for auth in (0,1):
  for shared in (0,1):
   B=S/'receiver'/f'w{width}_a{auth}_s{shared}';B.mkdir(parents=True,exist_ok=False);expected=cap[:]
   if shared:expected[10]+=expected[15];expected[15]=0
   expectedword=sum(x<<((width+1)*i) for i,x in enumerate(expected));bits=20*(width+1)
   tb=f'''`timescale 1ns/1ps // 发布器与实际TL接收端功能测试
module tb; // tb测试模块：实际FC建立容量并返回已扣CMD信用
reg clk=0;always #5 clk=~clk;reg rstn=0,start=0;integer cycles=0,paid=0,received=0,complete_count=0,returned=0;reg [7:0] owed=0; // 确定性运行和退休模型
wire pv,pt,pc,ps,pdone,rr,rt,pactive;wire [31:0] pw;wire [179:0] pending;wire [3:0] release_amount; // 实际发布输出
wire [511:0] rx_flit;wire [1:0] rx_msg;wire rxallowed,rxtaken,done,fatal,txtaken;wire [{bits-1}:0] capacity,available;wire link_enable; // 实际接收及信用账本
assign release_amount=owed>8'd15?4'd15:owed[3:0]; // 模型仅归还前一沿已实际扣除的CMD信用
assign link_enable=(cycles%4!=1);assign rx_flit=pc?{{247'd0,ps,8'd1,256'd0}}:{{480'd0,pw}};assign rx_msg=pc?2'd2:2'd0; // 标准FC与MSG1实际线上编码
 tl_credit_publish #(.WIDTH(8)) publisher(.i_clk(clk),.i_rstn(rstn),.i_start(start),.i_shared(1'b{shared}),.i_capacities(160'h{capword:x}),.o_start_ready(),.o_start_taken(),.o_config_error(),.i_release_valid(owed!=0),.i_releases({{76'd0,release_amount}}),.o_release_ready(rr),.o_release_taken(rt),.i_send(link_enable&&rxallowed),.o_valid(pv),.o_taken(pt),.o_complete(pc),.o_shared(ps),.o_word(pw),.o_active(pactive),.o_done(pdone),.o_pending(pending),.o_state()); // 实际20槽发布器
 tl_credit_port #(.WIDTH({width})) receiver(.i_clk(clk),.i_rstn(rstn),.i_receive(pv&&link_enable),.i_send(done&&pdone&&paid<24&&(cycles%5!=1)),.i_auth(1'b{auth}),.i_rx_flit(rx_flit),.i_rx_msg(rx_msg),.i_tx_flit(512'h{((1<<124)|(3<<118)|(1<<102)):x}),.i_tx_msg(2'd0),.o_rx_allowed(rxallowed),.o_rx_taken(rxtaken),.o_tx_taken(txtaken),.o_fatal(fatal),.o_done(done),.o_capacity(capacity),.o_available(available)); // 实际字段、内容、上下文与信用账本
always @(posedge clk)begin // 接受事件独立计数
 if(!rstn)begin owed<=0;paid<=0;end
 else begin
  owed<=owed+{{7'd0,txtaken}}-(rt?{{4'd0,release_amount}}:8'd0); // 每次实际付费发送仅生成一次模型退休
  if(txtaken)paid<=paid+1;
  if(rxtaken)received<=received+1;
  if(pt&&pc)complete_count<=complete_count+1;
  if(pt&&!pc&&pdone)returned<=returned+pw[24:22]; // 正常CMD Pool返回字段
  if(pt!==rxtaken)$fatal(1,"publisher and receiver commit differ");
 end
end // 结束实际事件计数
initial begin // 初始化、付费请求及实际FC归还闭环
 repeat(2)@(negedge clk);rstn=1;start=1;@(negedge clk);start=0;
 while(cycles<5000 && !(done&&pdone&&paid==24&&owed==0&&pending==0&&!pv))begin
  @(posedge clk);#1;cycles=cycles+1;
  if(fatal)$fatal(1,"actual receiver rejected FC/message");
  if(done&&capacity!=={bits}'h{expectedword:x})$fatal(1,"actual initial capacity/shared pool");
 end
 if(cycles==5000||paid!=24||returned!=24||complete_count!=1||available!==capacity)$fatal(1,"actual credit loop terminal");
 $display("PASS receiver width={width} auth={auth} shared={shared} cycles=%0d received=%0d paid=%0d returned=%0d",cycles,received,paid,returned);$finish;
end // 结束实际端口信用闭环测试
endmodule // 结束实际FC接收测试模块
''';(B/'tb.v').write_text(tb);cmd=['iverilog','-g2005','-s','tb','-o',str(B/'sim.vvp'),*[str(p) for p in sources],str(B/'tb.v')];(B/'command.json').write_text(json.dumps(cmd,indent=2)+'\n');x=subprocess.run(cmd,capture_output=True,text=True);(B/'compile.log').write_text(x.stdout+x.stderr);r=dict(width=width,auth=auth,shared=shared,compile_exit_status=x.returncode,passed=False)
   if x.returncode==0:
    x=subprocess.run(['vvp',str(B/'sim.vvp')],capture_output=True,text=True,timeout=60);(B/'run.log').write_text(x.stdout+x.stderr);r.update(run_exit_status=x.returncode,passed=x.returncode==0 and 'PASS receiver' in x.stdout);print(x.stdout,flush=True)
   else:print(x.stdout+x.stderr,flush=True)
   rows.append(r);(S/'receiver.json').write_text(json.dumps(dict(complete=len(rows)==8 and all(x['passed'] for x in rows),results=rows,sources={str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}),indent=2)+'\n')
raise SystemExit(0 if all(x['passed'] for x in rows) else 1)

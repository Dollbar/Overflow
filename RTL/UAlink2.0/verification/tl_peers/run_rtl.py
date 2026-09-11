"""Run python3 from project root [--label NAME --rtl PATH --corrupt].
Writes two actual RTL peers, scripted consumers, exact payload scoreboards and results.
Next actual receive storage/release RTL; the consumer and digital links are abstractions.
"""
from pathlib import Path
import argparse,json,subprocess,sys,itertools
R=Path(__file__).resolve().parents[2];D=R;S=R/'build/verification/tl_peers';S.mkdir(parents=True,exist_ok=True);sys.path.insert(0,str(R/'model/tl'))
from credit_context import Context
RTL=R/'rtl/tl'
p=argparse.ArgumentParser();p.add_argument('--label',default='traced');p.add_argument('--rtl',type=Path);p.add_argument('--corrupt',action='store_true');a=p.parse_args();top=a.rtl or RTL/'tl_credit_port.v';results=[]
def fc(lane,cmd=0,data=0,role=None):
 word=0
 for r in (0,1) if role is None else (role,):
  for offset,bits,amount in ((22 if r==0 else 16,3,cmd),(8 if r==0 else 0,5,data)):
   v=amount if lane==0 else amount|((lane-1)<<bits)|(1<<(bits+2))
   word|=v<<offset
 return word

def transaction(j,side):
 k=(j+side)%5+1;lane=(j//2)%5;vc=0 if lane==0 else lane-1;pool=int(lane==0);n=0 if k==4 else j%4
 if k==1:w=(1<<124)|(0x23<<118)|(vc<<116)|(pool<<102)|n
 elif k==2:w=(2<<60)|(vc<<58)|(pool<<46)|(n<<44)|(1<<37)
 elif k==3:w=(3<<60)|(3<<57)|(vc<<55)|(pool<<41)|(n<<39)
 elif k==4:w=(4<<28)|(vc<<26)|(pool<<14)
 else:w=(5<<28)|(vc<<26)|(pool<<14)|(n<<2)|2
 return w,lane,0 if k in (1,3) else 1,n+1,k==3

def payload(side,j,token):
 return sum((((side+1)<<28)|(j<<16)|(token<<8)|byte)<<(32*byte) for byte in range(8))

def scripts(auth,shared):
 streams=[];expected=[];descs=[];complete=[]
 for side in (0,1):
  ctx=Context(auth=bool(auth));stream=[dict(flit=fc(l,1,4),msg=0,gate=0) for l in range(5)]+[dict(flit=(1|(shared<<8))<<256,msg=2,gate=0)];exp=[];desc=[];ends=[]
  for j in range(24):
   word,lane,role,beats,be=transaction(j,side);desc.append(dict(lane=lane,role=role,beats=beats,byte_enable=be));first=True;token=0
   while first or ctx.pending:
    low=word if first else 0;proposal=ctx.step(low,transfer=False);halves=[low,0]
    for h,kind in enumerate(proposal['classes']):
     if kind in ('DATA','BYTE_ENABLE'):
      halves[h]=payload(side,j,token);exp.append((1 if kind=='DATA' else 2,halves[h]));token+=1
    ctx.step(halves[0]);stream.append(dict(flit=(halves[1]<<256)|halves[0],msg=0,gate=0));first=False
   if token!=beats*2+int(be):raise RuntimeError('independent token count')
   ends.append(len(exp));stream.append(dict(return_for=j,flit=0,msg=0,gate=0))
  streams.append(stream);expected.append(exp);descs.append(desc);complete.append(ends)
 for side in (0,1):
  for row in streams[side]:
   if 'return_for' in row:
    j=row['return_for'];peer=1-side;desc=descs[peer][j];row.update(flit=fc(desc['lane'],1,desc['beats'],desc['role']),gate=complete[peer][j])
 return streams,expected,descs

configs=list(itertools.product((8,16),(0,1),(0,1),(1,3)))
for width,auth,shared,latency in configs:
 B=S/a.label/f'w{width}_a{auth}_s{shared}_l{latency}';B.mkdir(parents=True,exist_ok=False);streams,expected,descs=scripts(auth,shared)
 for side in (0,1):
  (B/f'tx{side}.hex').write_text('\n'.join(f'{(r["gate"]<<514)|(r["msg"]<<512)|r["flit"]:0137x}' for r in streams[side])+'\n')
  # Receiver side consumes the opposite sender's list.
  (B/f'rx{side}.hex').write_text('\n'.join(f'{(k<<256)|w:065x}' for k,w in expected[1-side])+'\n')
 (B/'schedule.json').write_text(json.dumps(dict(transactions=descs,streams=streams,expected_tokens=[len(x) for x in expected]),indent=2)+'\n')
 sizes=[len(x) for x in streams];tokens=[len(expected[1-i]) for i in (0,1)]
 v=f'''`timescale 1ns/1ps // 数字测试单位
module tb; // 两实际RTL端口，消费模型明确为测试端
reg clk=0;always #5 clk=~clk; // 输入时钟
reg rstn=0;integer cycles=0,txidx0=0,txidx1=0,rxidx0=0,rxidx1=0,frames0=0,frames1=0,wait0=0,wait1=0,h,slot; // 独立计数
reg [545:0] script0[0:{sizes[0]-1}],script1[0:{sizes[1]-1}];reg [258:0] expect0[0:{tokens[0]-1}],expect1[0:{tokens[1]-1}]; // 只读脚本与独立payload预期
reg [511:0] tx0,tx1;reg [1:0] tm0,tm1;reg send0,send1; // 各自等待/提交
reg [511:0] link0[0:{latency-1}],link1[0:{latency-1}];reg [1:0] lm0[0:{latency-1}],lm1[0:{latency-1}];reg [{latency-1}:0] lv0=0,lv1=0; // 显式数字流水链路
wire [511:0] rx0=link0[{latency-1}],rx1=link1[{latency-1}];wire [1:0] rm0=lm0[{latency-1}],rm1=lm1[{latency-1}];wire rv0=lv0[{latency-1}],rv1=lv1[{latency-1}]; // 入站实际Flit
wire taken0,taken1,done0,done1,fatal0,fatal1,rt0,rt1,err0,err1;wire [2:0] rl0,rh0,rl1,rh1;wire [5:0] classes0={{rh0,rl0}},classes1={{rh1,rl1}};wire [{20*(width+1)-1}:0] cap0,cap1,avail0,avail1; // 真实观察
wire [6:0] rp0,rp1,tp0,tp1; // 两方向未决序列
always @* begin // 稳定候选仅在taken后换下一条
 tx0=0;tx1=0;tm0=0;tm1=0;send0=0;send1=0;
 if(txidx0<{sizes[0]})begin tx0=script0[txidx0][511:0];tm0=script0[txidx0][513:512];send0=(rxidx0>=script0[txidx0][545:514])&&(cycles%5!=1);end
 if(txidx1<{sizes[1]})begin tx1=script1[txidx1][511:0];tm1=script1[txidx1][513:512];send1=(rxidx1>=script1[txidx1][545:514])&&(cycles%7!=3);end
end // 源脚本结束
 tl_credit_port #(.WIDTH({width})) a(.i_clk(clk),.i_rstn(rstn),.i_receive(rv0),.i_send(send0),.i_auth(1'b{auth}),.i_rx_flit(rx0),.i_rx_msg(rm0),.i_tx_flit(tx0),.i_tx_msg(tm0),.o_tx_taken(taken0),.o_tx_error(err0),.o_rx_taken(rt0),.o_rx_lower(rl0),.o_rx_upper(rh0),.o_done(done0),.o_fatal(fatal0),.o_capacity(cap0),.o_available(avail0),.o_rx_pending(rp0),.o_tx_pending(tp0)); // 端口A
 tl_credit_port #(.WIDTH({width})) b(.i_clk(clk),.i_rstn(rstn),.i_receive(rv1),.i_send(send1),.i_auth(1'b{auth}),.i_rx_flit(rx1),.i_rx_msg(rm1),.i_tx_flit(tx1),.i_tx_msg(tm1),.o_tx_taken(taken1),.o_tx_error(err1),.o_rx_taken(rt1),.o_rx_lower(rl1),.o_rx_upper(rh1),.o_done(done1),.o_fatal(fatal1),.o_capacity(cap1),.o_available(avail1),.o_rx_pending(rp1),.o_tx_pending(tp1)); // 端口B
wire [79:0] demands0,demands1;assign demands0=a.o_demands;assign demands1=b.o_demands; // 观察完整信用需求
integer trace;initial trace=$fopen("{B}/trace.txt","w"); // 独立逐周期审计
integer stage; // 数字链路级数
always @(posedge clk)begin // 链路捕获实际发送，检查当前实际接收
 if(!rstn)begin lv0<=0;lv1<=0;end
 else begin
  $fdisplay(trace,"P %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h",cycles,txidx0,txidx1,rxidx0,rxidx1,send0,send1,taken0,taken1,rv0,rv1,rt0,rt1,done0,done1,tx0,tx1,tm0,tm1,rx0,rx1,rm0,rm1,classes0,classes1,demands0,demands1,cap0,cap1,avail0,avail1,rp0,rp1,tp0,tp1);
  lv0[0]<=taken1;lv1[0]<=taken0;link0[0]<=tx1;link1[0]<=tx0;lm0[0]<=tm1;lm1[0]<=tm0;
  if({int(a.corrupt)} && taken0 && txidx0==7)link1[0]<=tx0^(512'd1<<300); // 明确单bit链路故障，健康为常零
  for(stage=1;stage<{latency};stage=stage+1)begin lv0[stage]<=lv0[stage-1];lv1[stage]<=lv1[stage-1];link0[stage]<=link0[stage-1];link1[stage]<=link1[stage-1];lm0[stage]<=lm0[stage-1];lm1[stage]<=lm1[stage-1];end
  if(rt0)begin frames0=frames0+1;for(h=0;h<2;h=h+1)if(classes0[h*3+:3]==1||classes0[h*3+:3]==2)begin
   if(rxidx0>={tokens[0]}||expect0[rxidx0]!=={{classes0[h*3+:3],rx0[h*256+:256]}})$fatal(1,"payload/order A index %0d",rxidx0);rxidx0=rxidx0+1;end end
  if(rt1)begin frames1=frames1+1;for(h=0;h<2;h=h+1)if(classes1[h*3+:3]==1||classes1[h*3+:3]==2)begin
   if(rxidx1>={tokens[1]}||expect1[rxidx1]!=={{classes1[h*3+:3],rx1[h*256+:256]}})$fatal(1,"payload/order B index %0d",rxidx1);rxidx1=rxidx1+1;end end
  if(send0&&!taken0)wait0=wait0+1;if(send1&&!taken1)wait1=wait1+1;
  if(taken0)txidx0<=txidx0+1;if(taken1)txidx1<=txidx1+1;
  #0.1;$fdisplay(trace,"Q %0d %0d %0d %0h %0h %0h %0h %0h %0h",cycles,done0,done1,cap0,cap1,avail0,avail1,fatal0,fatal1); // NBA后状态先于终态检查
 end
end // 实际接收消费后才释放门限
initial begin // 独立容量及排空检查
 $readmemh("{B}/tx0.hex",script0);$readmemh("{B}/tx1.hex",script1);$readmemh("{B}/rx0.hex",expect0);$readmemh("{B}/rx1.hex",expect1);
 repeat(2)@(negedge clk);rstn=1;
 while(cycles<5000 && !(txidx0=={sizes[0]}&&txidx1=={sizes[1]}&&frames0=={sizes[1]}&&frames1=={sizes[0]}))begin
  @(posedge clk);#1;cycles=cycles+1;if(fatal0||fatal1)$fatal(1,"peer fatal cycle %0d",cycles);if((send0&&err0)||(send1&&err1))$fatal(1,"invalid scripted source");
 end
 if(cycles==5000||!done0||!done1||rxidx0!={tokens[0]}||rxidx1!={tokens[1]}||rp0||rp1||tp0||tp1)$fatal(1,"deadlock/count/pending");
 for(slot=0;slot<20;slot=slot+1)begin
  if(cap0[slot*{width+1}+:{width+1}]!=(slot<10?1:({shared}&&slot==10?8:({shared}&&slot==15?0:4))))$fatal(1,"initial capacity A");
  if(cap1[slot*{width+1}+:{width+1}]!==cap0[slot*{width+1}+:{width+1}])$fatal(1,"initial capacity B");
 end
 if(avail0!==cap0||avail1!==cap1)$fatal(1,"credit conservation after release");
 $display("PASS peers width={width} auth={auth} shared={shared} latency={latency} cycles=%0d frames=%0d tokens=%0d waits=%0d",cycles,frames0+frames1,rxidx0+rxidx1,wait0+wait1);$finish;
end // 结束
endmodule // 双端完整payload验证
''';(B/'tb.v').write_text(v);cmd=['iverilog','-g2005','-s','tb','-o',str(B/'sim.vvp'),str(top),*[str(p) for p in [p for p in sorted(RTL.glob('*.v')) if p.name not in ('tl_receive_storage.v','tl_receive_context.v','tl_credit_publish.v')] if p.name!='tl_credit_port.v'],str(B/'tb.v')];x=subprocess.run(cmd,capture_output=True,text=True);(B/'compile.log').write_text(x.stdout+x.stderr);row=dict(width=width,auth=auth,shared=shared,latency=latency,compile_exit_status=x.returncode,passed=False,expected_frames=sum(sizes),expected_tokens=sum(tokens))
 if x.returncode==0:
  x=subprocess.run(['vvp',str(B/'sim.vvp')],capture_output=True,text=True,timeout=60);(B/'run.log').write_text(x.stdout+x.stderr);row.update(run_exit_status=x.returncode,passed=x.returncode==0 and 'PASS peers' in x.stdout);print(x.stdout,flush=True)
 results.append(row);(S/(a.label+'.json')).write_text(json.dumps(dict(results=results,complete=len(results)==len(configs) and all(x['passed'] for x in results)),indent=2)+'\n')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)

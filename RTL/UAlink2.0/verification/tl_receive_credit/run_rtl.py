"""Run: python3 verification/tl_receive_credit/run_rtl.py --kd28-root PATH.
Outputs fresh actual dual-port/SRAM/FC runs and independently checked stored words.
Use --data-credits 1 to diagnose mid-tenure small-credit liveness; timeouts fail.
Next: resolve any liveness counterexample, then full online capacity induction/STA.
"""
from pathlib import Path
import argparse,hashlib,itertools,json,subprocess,sys,shutil
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'model/tl'))
from credit_context import Context
from receive_context import ReceiveContext
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label',default='matrix');p.add_argument('--data-credits',type=int,choices=(1,4),default=4);p.add_argument('--single',action='store_true');p.add_argument('--replace',type=Path);p.add_argument('--traffic-pressure',action='store_true');p.add_argument('--admission',action='store_true');a=p.parse_args()
S=R/'build/verification/tl_receive_credit'/a.label;S.mkdir(parents=True,exist_ok=False)
external=[a.kd28_root/'Library/models/kd28/sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[a.kd28_root/'Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v']
sources=sorted((R/'rtl/tl').glob('*.v'))+[R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v']
if a.replace:sources=[a.replace if x.name==a.replace.name else x for x in sources]
classes={'CONTROL':0,'DATA':1,'BYTE_ENABLE':2,'NOP':3,'MESSAGE':4,'POISON':5,'AUTH':6,'RESET':7}
def pack(v,b):return sum(x<<(i*b) for i,x in enumerate(v))
def stream(auth,side):
    ctx=Context(auth=bool(auth));rx=ReceiveContext(auth=bool(auth));out=[];expected=[]
    for j in range(30):
        kind=(j+side)%5+1;lane=(j//5)%5;vc=max(lane-1,0);pool=int(lane==0);n=j%4
        if a.traffic_pressure:kind=1 if (j//2)%2==0 else 2;vc=0;pool=0;n=2
        if kind==1:word=(1<<124)|(0x23<<118)|(vc<<116)|(pool<<102)|n
        elif kind==2:word=(2<<60)|(vc<<58)|(pool<<46)|(n<<44)|(1<<37)
        elif kind==3:word=(3<<60)|(3<<57)|(vc<<55)|(pool<<41)|(n<<39)
        elif kind==4:word=(4<<28)|(vc<<26)|(pool<<14)
        else:word=(5<<28)|(vc<<26)|(pool<<14)|(n<<2)|2
        first=True;token=0
        while first or ctx.pending:
            low=word if first else 0;proposal=ctx.step(low,transfer=False);halves=[low,0]
            for h,k in enumerate(proposal['classes']):
                if k in ('DATA','BYTE_ENABLE'):
                    halves[h]=sum((((side+1)<<28)|(j<<16)|(token<<8)|b)<<(32*b) for b in range(8));token+=1
            ctx.step(halves[0]);saved=rx.step(halves[0]);flit=halves[0]|(halves[1]<<256);out.append(flit)
            if not saved['store']:raise RuntimeError('application word without stored resource')
            expected.append((pack(saved['releases'],4)<<520)|(pack([classes[x] for x in saved['classes']],3)<<514)|flit)
            first=False
    return out,expected
configs=list(itertools.product((8,16),(0,1),(0,1),(1,3)))
if a.single:configs=configs[:1]
rows=[]
for width,auth,shared,latency in configs:
    B=S/f'w{width}_a{auth}_s{shared}_l{latency}';B.mkdir();cmdcredits=2 if a.traffic_pressure else 1;caps=[cmdcredits]*10+[a.data_credits]*10;depth=2*sum(caps);cw=depth.bit_length();capword=pack(caps,width);ledger=caps[:]
    if shared:ledger[10]+=ledger[15];ledger[15]=0
    expectedcap=pack(ledger,width+1);streams=[stream(auth,i) for i in (0,1)];sizes=[len(x[0]) for x in streams];N=max(sizes)
    for side,(flits,expected) in enumerate(streams):
        (B/f'app{side}.hex').write_text('\n'.join(f'{x:0128x}' for x in flits)+'\n');(B/f'expected{side}.hex').write_text('\n'.join(f'{x:0150x}' for x in expected)+'\n')
    bits=20*(width+1)
    admission_ports=',.o_admission_wait(admission_wait[side]),.o_capacity_shortfall(shortfall[side]),.o_requirements(requirements[side])' if a.admission else ''
    admission_trace=f'''integer admission_trace;initial admission_trace=$fopen("{B}/admission_trace.txt","w");
always @(posedge clk)if(rstn)for(integer ae=0;ae<2;ae=ae+1)begin
 $fdisplay(admission_trace,"%0d %0d %0d %0d %0d %0d %0d %0d %0h %0h %0h",cycle,ae,send[ae],taken[ae],txpending[ae],admission_wait[ae],shortfall[ae],select_fc[ae],requirements[ae],available[ae],capacity[ae]);
 if((admission_wait[ae]||shortfall[ae])&&taken[ae])$fatal(1,"unfunded header sent");
end
''' if a.admission else ''
    tb=f'''`timescale 1ns/1ps // 实际双端信用闭环测试
module tb; // 两套真实端口与600位SRAM，信用仅由实际退休返回
reg clk=0;always #5 clk=~clk;reg rstn=0,start=0,bad_config=0;integer cycle=0,e,j,h,g,lane,amount,field,pos,nbits; // 单输入时钟及独立观察计数
reg [511:0] app0[0:{sizes[0]-1}],app1[0:{sizes[1]-1}];reg [599:0] expected0[0:{sizes[0]-1}],expected1[0:{sizes[1]-1}]; // 参考只记录应用实际数据与释放元数据
integer txidx[0:1],rxidx[0:1],fc_count[0:1],init_count[0:1],stalls[0:1];integer returned[0:1][0:19],published[0:1][0:19]; // 独立解码FC对照已消费信用
reg [511:0] link[0:1][0:{latency-1}];reg [1:0] message[0:1][0:{latency-1}];reg lv[0:1][0:{latency-1}]; // 有限延迟数字链路，不添加接收端物理ready
wire [511:0] rx[0:1],tx[0:1],fc[0:1],read_flit[0:1];wire [1:0] rm[0:1],tm[0:1],fm[0:1],read_msg[0:1]; // 双端完整Flit
wire rxv[0:1],taken[0:1],port_rxtaken[0:1],portfatal[0:1],peer_done[0:1]; // 实际信用端口
wire allowed[0:1],rxtaken[0:1],fatal[0:1],read_valid[0:1],retired[0:1],release_taken[0:1],read_ready[0:1]; // 实际SRAM消费
wire fv[0:1],ft[0:1],complete[0:1],active[0:1],done[0:1],sr[0:1],st[0:1],ce[0:1]; // 发布与配置握手
wire admission_wait[0:1],shortfall[0:1];wire [119:0] requirements[0:1]; // 整段准入本地观察
wire [79:0] releases[0:1];wire [5:0] read_classes[0:1];wire [{cw-1}:0] count[0:1];wire [{width+5}:0] required[0:1]; // 完整消费元数据与预算
wire [{bits-1}:0] pending[0:1],capacity[0:1],available[0:1];wire [6:0] txpending[0:1];wire select_fc[0:1],app_valid[0:1],send[0:1]; // 实际信用与发送候选
reg [511:0] app_word[0:1]; // 仅保持尚未实际发出的应用字
always @* begin // 不依赖任何软件信用返回模型
 app_word[0]=txidx[0]<{sizes[0]}?app0[txidx[0]]:512'd0;
 app_word[1]=txidx[1]<{sizes[1]}?app1[txidx[1]]:512'd0;
end // 应用输入来源结束
genvar side;generate for(side=0;side<2;side=side+1)begin:ends // 两端同一真实模块组合
 assign rx[side]=link[side][{latency-1}];assign rm[side]=message[side][{latency-1}];assign rxv[side]=lv[side][{latency-1}]; // 已发送Flit按固定延迟到达
 assign select_fc[side]=fv[side]&&(txpending[side]==0); // 当前基线仅在Data tenure边界放入Control FC
 assign app_valid[side]=(side==0?txidx[0]<{sizes[0]}:txidx[1]<{sizes[1]})&&done[side]&&peer_done[side]; // 初始交换完成才发应用
 assign tx[side]=select_fc[side]?fc[side]:app_word[side];assign tm[side]=select_fc[side]?fm[side]:2'd0; // 稳定候选按实际taken推进
 assign send[side]=(select_fc[side]||app_valid[side])&&(cycle%7!=side+1); // 明确发送停顿
 assign read_ready[side]=(cycle>80)&&(cycle%5!=side+1); // 消费者停顿，不能触发提前归还
 tl_receive_credit #(.WIDTH({width}),.DEPTH({depth})) storage(.i_clk(clk),.i_rstn(rstn),.i_start(start),.i_shared(1'b{shared}),.i_auth(1'b{auth}),.i_capacities(bad_config?{{{20*width}{{1'b1}}}}:{20*width}'h{capword:x}),.o_start_ready(sr[side]),.o_start_taken(st[side]),.o_config_error(ce[side]),.o_required_words(required[side]),.i_valid(rxv[side]),.i_flit(rx[side]),.i_msg(rm[side]),.o_allowed(allowed[side]),.o_taken(rxtaken[side]),.o_rejected(),.o_fatal(fatal[side]),.i_read_ready(read_ready[side]),.o_read_valid(read_valid[side]),.o_read_flit(read_flit[side]),.o_read_msg(read_msg[side]),.o_read_classes(read_classes[side]),.o_read_releases(releases[side]),.o_retired(retired[side]),.i_fc_send(select_fc[side]&&taken[side]),.o_fc_valid(fv[side]),.o_fc_taken(ft[side]),.o_fc_complete(complete[side]),.o_fc_flit(fc[side]),.o_fc_msg(fm[side]),.o_active(active[side]),.o_done(done[side]),.o_pending(pending[side]),.o_count(count[side]),.o_release_taken(release_taken[side])); // 真实存储产生信用
 {'tl_credit_admitted_port' if a.admission else 'tl_credit_port'} #(.WIDTH({width})) port(.i_clk(clk),.i_rstn(rstn),.i_receive(rxv[side]),.i_send(send[side]),.i_auth(1'b{auth}),.i_rx_flit(rx[side]),.i_rx_msg(rm[side]),.i_tx_flit(tx[side]),.i_tx_msg(tm[side]),.o_rx_taken(port_rxtaken[side]),.o_tx_taken(taken[side]),.o_fatal(portfatal[side]),.o_done(peer_done[side]),.o_capacity(capacity[side]),.o_available(available[side]),.o_tx_pending(txpending[side]){admission_ports}); // 实际字段扣费与对端FC更新
end endgenerate // 两端真实实例结束
{admission_trace}
integer trace;initial trace=$fopen("{B}/trace.txt","w"); // 每拍保留实际链路与所有权观察
always @(posedge clk)begin // 更新只由实际握手和真实保存字驱动
 if(!rstn)begin
  for(e=0;e<2;e=e+1)begin txidx[e]=0;rxidx[e]=0;fc_count[e]=0;init_count[e]=0;stalls[e]=0;for(j=0;j<20;j=j+1)begin returned[e][j]=0;published[e][j]=0;end
   for(j=0;j<{latency};j=j+1)begin lv[e][j]<=0;link[e][j]<=0;message[e][j]<=0;end
  end
 end else begin
  for(e=0;e<2;e=e+1)begin
   $fdisplay(trace,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0h %0h %0h %0h",cycle,e,txidx[e],rxidx[e],rxv[e],rxtaken[e],taken[e],select_fc[e],ft[e],retired[e],release_taken[e],count[e],releases[e],pending[e],available[e],tx[e]); // 原始观察可独立重核
   if(fatal[e]||portfatal[e])$fatal(1,"actual receive fatal");
   if(rxv[e]&&(!allowed[e]||!rxtaken[e]||!port_rxtaken[e]))$fatal(1,"inflight flit lacks actual capacity or atomic admission");
   if(retired[e]!==release_taken[e]||retired[e]!== (read_valid[e]&&read_ready[e]))$fatal(1,"consumption release not atomic");
   if(read_valid[e]&&!read_ready[e])stalls[e]=stalls[e]+1;
   if(retired[e])begin
    if(e==0)begin if(rxidx[e]>={sizes[1]}||{{releases[e],read_classes[e],read_msg[e],read_flit[e]}}!==expected1[rxidx[e]])$fatal(1,"stored word A ownership/payload %0d",rxidx[e]);end
    else begin if(rxidx[e]>={sizes[0]}||{{releases[e],read_classes[e],read_msg[e],read_flit[e]}}!==expected0[rxidx[e]])$fatal(1,"stored word B ownership/payload %0d",rxidx[e]);end
    rxidx[e]=rxidx[e]+1;for(j=0;j<20;j=j+1)returned[e][j]=returned[e][j]+releases[e][j*4+:4];
   end
   if(ft[e])begin
    if(complete[e])begin
     for(j=0;j<20;j=j+1)if(published[e][j]!=(j<10?{cmdcredits}:{a.data_credits}))$fatal(1,"initial credit capacity differs");
     init_count[e]=init_count[e]+1;
    end else begin
     fc_count[e]=fc_count[e]+1;
     for(g=0;g<4;g=g+1)begin
      pos=g==0?22:g==1?16:g==2?8:0;nbits=g<2?3:5;field=(fc[e]>>pos)&((1<<(nbits+3))-1);amount=field&((1<<nbits)-1);lane=(field&(1<<(nbits+2)))?1+((field>>nbits)&3):0;
      published[e][g*5+lane]=published[e][g*5+lane]+amount;
      if(published[e][g*5+lane]>(g<2?{cmdcredits}:{a.data_credits})+returned[e][g*5+lane])$fatal(1,"credit published before actual retirement");
     end
    end
   end
   if(peer_done[e]&&capacity[e]!=={bits}'h{expectedcap:x})$fatal(1,"peer capacity/shared initial credits");
   if(taken[e]&&!select_fc[e])txidx[e]=txidx[e]+1;
   lv[1-e][0]<=taken[e];link[1-e][0]<=tx[e];message[1-e][0]<=tm[e];
   for(j=1;j<{latency};j=j+1)begin lv[e][j]<=lv[e][j-1];link[e][j]<=link[e][j-1];message[e][j]<=message[e][j-1];end
  end
 end
end // 实际事件核对结束
initial begin // 错误配置、正常初始化、持续双端负载与完全排空
 $readmemh("{B}/app0.hex",app0);$readmemh("{B}/app1.hex",app1);$readmemh("{B}/expected0.hex",expected0);$readmemh("{B}/expected1.hex",expected1);
 repeat(3)@(negedge clk);rstn=1;start=1;bad_config=1;#1;
 if(st[0]||st[1]||!ce[0]||!ce[1])$fatal(1,"overcommitted configuration accepted");
 @(negedge clk);bad_config=0;#1;if(!st[0]||!st[1]||ce[0]||ce[1]||required[0]!={depth})$fatal(1,"exact capacity budget rejected");
 @(negedge clk);start=0;
 while(cycle<6000&&!(txidx[0]=={sizes[0]}&&txidx[1]=={sizes[1]}&&rxidx[0]=={sizes[1]}&&rxidx[1]=={sizes[0]}&&pending[0]==0&&pending[1]==0&&!fv[0]&&!fv[1]&&available[0]==capacity[0]&&available[1]==capacity[1]))begin @(negedge clk);cycle=cycle+1;end
 if(cycle>=6000)begin $display("STALLED tx=%0d/%0d rx=%0d/%0d pending=%0d/%0d FIFO=%0d/%0d",txidx[0],txidx[1],rxidx[0],rxidx[1],txpending[0],txpending[1],count[0],count[1]);$fatal(1,"dual actual storage/FC liveness timeout");end
 for(e=0;e<2;e=e+1)begin
  if(count[e]!=0||init_count[e]!=1||fc_count[e]<6||stalls[e]==0)$fatal(1,"terminal coverage");
  for(j=0;j<20;j=j+1)if(published[e][j]!=(j<10?{cmdcredits}:{a.data_credits})+returned[e][j])$fatal(1,"terminal credit conservation");
 end
 $display("PASS actual dual SRAM FC width={width} auth={auth} shared={shared} latency={latency} cycles=%0d stored=%0d fc=%0d",cycle,rxidx[0]+rxidx[1],fc_count[0]+fc_count[1]);$finish;
end // 完整排空后完成
endmodule // 测试结束
'''
    (B/'tb.v').write_text(tb);cmd=['iverilog','-g2012','-s','tb','-o',str(B/'sim.vvp'),*[str(x) for x in sources+external],str(B/'tb.v')]
    cp=subprocess.run(cmd,capture_output=True,text=True);(B/'compile.log').write_text(cp.stdout+cp.stderr);row=dict(width=width,auth=auth,shared=shared,latency=latency,depth=depth,compile_exit=cp.returncode,passed=False)
    if cp.returncode==0:
        x=subprocess.run(['vvp',str(B/'sim.vvp')],capture_output=True,text=True,timeout=120);(B/'run.log').write_text(x.stdout+x.stderr);row.update(run_exit=x.returncode,passed=x.returncode==0 and 'PASS actual dual SRAM FC' in x.stdout);print(x.stdout,flush=True)
        if row['passed']:shutil.copy2(B/'trace.txt',B/'healthy_trace.txt')
    rows.append(row);(S/'results.json').write_text(json.dumps(dict(complete=len(rows)==len(configs) and all(x['passed'] for x in rows),results=rows,sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+external}),indent=2)+'\n')
raise SystemExit(0 if all(x['passed'] for x in rows) else 1)

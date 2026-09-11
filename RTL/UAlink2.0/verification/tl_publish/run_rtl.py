"""Run python3 verification/tl_publish/run_rtl.py [--rtl PATH --label NAME].
Writes actual clock vectors, full state/FC scoreboards, compile and execution logs.
Next actual receiving TL port, faults, synthesis and independent evidence audit.
"""
from pathlib import Path
import argparse,json,random,sys,subprocess
R=Path(__file__).resolve().parents[2];D=R;S=R/'build/verification/tl_publish';S.mkdir(parents=True,exist_ok=True);sys.path.insert(0,str(R/'model/tl'))
from credit_publish import Publisher
p=argparse.ArgumentParser();p.add_argument('--rtl',type=Path,default=R/'rtl/tl/tl_credit_publish.v');p.add_argument('--label',default='final');a=p.parse_args();results=[]
def packed(values,width):return sum(int(v)<<(i*width) for i,v in enumerate(values))
def state(p):return (((((int(p.active)<<1|int(p.done))<<1|int(p.shared))<<1|int(p.valid))<<1|int(p.complete))<<(44+20*(p.width+1)))|(p.word<<(12+20*(p.width+1)))|(packed(p.pointer,3)<<(20*(p.width+1)))|packed(p.pending,p.width+1)
for width in (1,3,8,16):
 for shared in (0,1):
  B=S/'sim'/a.label/f'w{width}_s{shared}';B.mkdir(parents=True,exist_ok=False);model=Publisher(width);rng=random.Random(510+width+shared);rows=[];coverage=dict(starts=0,fc=0,complete=0,releases=0,stall=0,backpressure=0,concurrent=0)
  def emit(start=False,cap=None,mode=shared,release_valid=False,release=None,send=False,reset=False):
   cap=cap if cap is not None else [rng.randrange(1<<width) for _ in range(20)];rel=release if release is not None else [0]*20
   r=model.step(start=start,capacities=cap,shared=bool(mode),release_valid=release_valid,release=rel,send=send,reset=reset)
   flags=0
   for key in ('start_ready','start_taken','config_error','release_ready','release_taken','valid','taken','complete','shared'):flags=flags<<1|int(r[key])
   flags=(flags<<32)|r['word'];rows.append(f'{int(not reset)} {int(start)} {int(mode)} {packed(cap,width):x} {int(release_valid)} {packed(rel,4):x} {int(send)} {flags:x} {state(model):x}')
   coverage['starts']+=r['start_taken'];coverage['fc']+=r['taken'] and not r['complete'];coverage['complete']+=r['taken'] and r['complete'];coverage['releases']+=r['release_taken'];coverage['stall']+=r['valid'] and not send;coverage['backpressure']+=release_valid and not r['release_ready'];coverage['concurrent']+=r['taken'] and not r['complete'] and r['release_taken']
  emit(reset=True);emit(start=True,cap=[0]*20,mode=0)
  cap=[min((i*13+11)%97,(1<<width)-1) for i in range(20)];cap[10]=cap[15]=min(65,(1<<width)-1)
  if width==16:cap[0]=65535
  emit(start=True,cap=cap)
  for _ in range(25):emit(release_valid=True,release=[1]*20)
  guard=0
  while not model.done:
   emit(send=guard%7!=3,release_valid=True,release=[1]*20);guard+=1
   if guard>100000:raise RuntimeError('init timeout')
  # Force an observable, nonzero release simultaneous with a held FC even at WIDTH1.
  one=[0]*20;one[0]=1;emit(release_valid=True,release=one);emit()
  if not model.valid or model.complete:raise RuntimeError('directed concurrent FC missing')
  emit(release_valid=True,release=one,send=True)
  if model.pending[0]!=1:raise RuntimeError('directed concurrent release lost')
  while any(model.pending) or model.valid:emit(send=True)
  for _ in range(800):
   rel=[0]*20
   for i in range(20):
    if rng.randrange(5)==0:rel[i]=rng.randrange(1,16)
   emit(release_valid=True,release=rel,send=rng.randrange(4)!=0,mode=1-shared)
  # Drain, then exercise exact highest pending counter and no same-cycle bypass.
  guard=0
  while any(model.pending) or model.valid:
   emit(send=True);guard+=1
   if guard>100000:raise RuntimeError('drain timeout')
  limit=(1<<(width+1))-1
  while model.pending[0]<limit:
   rel=[0]*20;rel[0]=min(15,limit-model.pending[0]);emit(release_valid=True,release=rel)
  one=[0]*20;one[0]=1;emit(release_valid=True,release=one,send=True)
  while any(model.pending) or model.valid:emit(send=True)
  # Reset during an actually stalled normal-credit offer, then initialize afresh.
  emit(release_valid=True,release=[1]*20);emit();emit();emit(reset=True)
  emit(start=True,cap=[min(1,(1<<width)-1)]*20)
  while not model.done:emit(send=True)
  emit();(B/'vectors.txt').write_text('\n'.join(rows)+'\n');N=len(rows);sw=49+20*(width+1)
  tb=f'''`timescale 1ns/1ps // 单时钟FC发布实际RTL回归
module tb; // tb测试模块：独立解码真实FC并检查所有信用守恒
reg clk=0;always #5 clk=~clk;reg rstn=0,start=0,shared=0,rv=0,send=0;reg [{20*width-1}:0] cap=0;reg [79:0] release_bus=0; // 外部真实输入
wire sr,st,ce,rr,rt,valid,taken,complete,mode,active,done;wire [31:0] word;wire [{20*(width+1)-1}:0] pending;wire [{sw-1}:0] actual; // 全部输出及状态
 tl_credit_publish #(.WIDTH({width})) dut(.i_clk(clk),.i_rstn(rstn),.i_start(start),.i_shared(shared),.i_capacities(cap),.o_start_ready(sr),.o_start_taken(st),.o_config_error(ce),.i_release_valid(rv),.i_releases(release_bus),.o_release_ready(rr),.o_release_taken(rt),.i_send(send),.o_valid(valid),.o_taken(taken),.o_complete(complete),.o_shared(mode),.o_word(word),.o_active(active),.o_done(done),.o_pending(pending),.o_state(actual)); // 实际发布器
integer fd,scan,row=0,nrst,nstart,nshare,nrv,nsend,i,g,field,lane,amount,pos,bits;integer balance[0:19];integer fc_count=0,complete_count=0,release_count=0,stall_count=0;reg seen_complete=0;reg [40:0] expected;reg [{sw-1}:0] expected_state; // 独立参考和实际事件计数
initial begin // 每行比较沿前提议和沿后全部寄存器
 fd=$fopen("{B}/vectors.txt","r");for(i=0;i<20;i=i+1)balance[i]=0;
 while(!$feof(fd))begin
  @(negedge clk);scan=$fscanf(fd,"%d %d %d %h %d %h %d %h %h\\n",nrst,nstart,nshare,cap,nrv,release_bus,nsend,expected,expected_state);
  if(scan!=9)$fatal(1,"vector syntax");rstn=nrst;start=nstart;shared=nshare;rv=nrv;send=nsend;#1;
  if({{sr,st,ce,rr,rt,valid,taken,complete,mode,word}}!==expected)$fatal(1,"publisher outputs row %0d",row);
  @(posedge clk);
  if(!rstn)begin for(i=0;i<20;i=i+1)balance[i]=0;seen_complete=0;end
  else begin
   if(st)for(i=0;i<20;i=i+1)balance[i]=cap[i*{width}+:{width}];
   if(rt)begin
    if(!seen_complete)$fatal(1,"release_bus before actual completion");release_count=release_count+1;
    for(i=0;i<20;i=i+1)balance[i]=balance[i]+release_bus[i*4+:4];
   end
   if(taken)begin
    if(complete)begin
     if(seen_complete)$fatal(1,"repeated complete");for(i=0;i<20;i=i+1)if(balance[i]!=0)$fatal(1,"complete before all initial credit sent");seen_complete=1;complete_count=complete_count+1;
    end else begin
     if(word==0||word[31:28]!=0)$fatal(1,"invalid FC type or empty FC");fc_count=fc_count+1;
     for(g=0;g<4;g=g+1)begin
      pos=g==0?22:g==1?16:g==2?8:0;bits=g<2?3:5;field=(word>>pos)&((1<<(bits+3))-1);amount=field&((1<<bits)-1);lane=(field&(1<<(bits+2)))?1+((field>>bits)&3):0;
      balance[g*5+lane]=balance[g*5+lane]-amount;if(balance[g*5+lane]<0)$fatal(1,"unowned or duplicate credit");
     end
    end
   end
   if(valid&&!send)stall_count=stall_count+1;
  end
  #1;if(actual!==expected_state)$fatal(1,"publisher state row %0d",row);
  for(i=0;i<20;i=i+1)if(pending[i*{width+1}+:{width+1}]!==balance[i])$fatal(1,"actual FC conservation row %0d slot %0d",row,i);
  row=row+1;
 end
 if(row!={N}||!done||valid||pending!=0||fc_count==0||complete_count!=2||release_count==0||stall_count==0)$fatal(1,"terminal or coverage");
 $display("PASS publish width={width} shared={shared} edges=%0d fc=%0d complete=%0d releases=%0d stalls=%0d",row,fc_count,complete_count,release_count,stall_count);$finish;
end // 结束逐周期发布与独立信用核对
endmodule // 结束发布器测试模块
''';(B/'tb.v').write_text(tb);cmd=['iverilog','-g2005','-s','tb','-o',str(B/'sim.vvp'),str(a.rtl),str(B/'tb.v')];(B/'command.json').write_text(json.dumps(cmd,indent=2)+'\n');x=subprocess.run(cmd,capture_output=True,text=True);(B/'compile.log').write_text(x.stdout+x.stderr);result=dict(width=width,shared=shared,edges=N,coverage=coverage,compile_exit_status=x.returncode,passed=False)
  if x.returncode==0:
   try:x=subprocess.run(['vvp',str(B/'sim.vvp')],capture_output=True,text=True,timeout=90);status,log=x.returncode,x.stdout+x.stderr
   except subprocess.TimeoutExpired as e:status,log=124,(e.stdout or b'').decode()+(e.stderr or b'').decode()
   (B/'run.log').write_text(log);result.update(run_exit_status=status,passed=status==0 and 'PASS publish' in log);print(log,flush=True)
  else:print(x.stdout+x.stderr,flush=True)
  results.append(result);(S/(a.label+'.json')).write_text(json.dumps(dict(complete=len(results)==8 and all(r['passed'] for r in results),results=results),indent=2)+'\n')
raise SystemExit(0 if all(x['passed'] for x in results) else 1)

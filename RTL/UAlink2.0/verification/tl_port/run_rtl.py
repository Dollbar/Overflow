"""Run python3 from project root [--rtl PATH --label NAME].
Writes actual Rx/Tx Flit vectors with full shared state checks. Next proof, faults and timing.
"""
from pathlib import Path
import argparse,json,subprocess,sys,random
R=Path(__file__).resolve().parents[2];D=R;S=R/'build/verification/tl_port';S.mkdir(parents=True,exist_ok=True);sys.path.insert(0,str(R/'model/tl'))
from credit_context import Context
from credit_integration import Integrated
from tx_validation import TxValidation
p=argparse.ArgumentParser();p.add_argument('--rtl',type=Path);p.add_argument('--label',default='healthy');a=p.parse_args();rtl=a.rtl or R/'rtl/tl/tl_credit_port.v';results=[]
C={'CONTROL':0,'DATA':1,'BYTE_ENABLE':2,'NOP':3,'MESSAGE':4,'POISON':5,'AUTH':6,'RESET':7}
def slots(v,w):return sum(x<<(i*w) for i,x in enumerate(v))
def pack(parts):
 n=0
 for v,w in parts:n=(n<<w)|int(v)
 return n
def field(k,vc,pool,n=0):
 if k==1:return (1<<124)|(0x23<<118)|(vc<<116)|(pool<<102)|n
 if k==2:return (2<<60)|(vc<<58)|(pool<<46)|(n<<44)|(1<<37)
 if k==3:return (3<<60)|(3<<57)|(vc<<55)|(pool<<41)|(n<<39)
 if k==4:return (4<<28)|(vc<<26)|(pool<<14)
 return (5<<28)|(vc<<26)|(pool<<14)|(n<<2)|2
def fc(lane,cmd=7,data=31):
 word=0
 for offset,bits,amount in ((22,3,cmd),(16,3,cmd),(8,5,data),(0,5,data)):
  value=amount if lane==0 else amount|((lane-1)<<bits)|(1<<(bits+2))
  word|=value<<offset
 return word
for width in (8,16):
 for auth in (0,1):
  context=Context(auth=bool(auth));rx=Integrated(width,bool(auth));tx=TxValidation(bool(auth));rows=[];coverage=dict(tx_taken=0,rx_taken=0,rx_rejected=0,tx_wait=0,context_error=0,rx_error_with_send=0);max_pending=0
  def emit(rlo=0,rhi=0,rmsg=0,tlo=0,thi=0,tmsg=0,receive=False,send=False,reset=False):
   global max_pending
   messages=tuple((v&255) if (tmsg>>i)&1 else None for i,v in enumerate((tlo,thi)))
   if reset:context.step(reset=True);proposal=dict(classes=('RESET','RESET'),demands=(0,)*20);valid=False;error=False
   else:
    try:proposal=context.step(tlo,msg=messages,transfer=False);valid=True
    except ValueError:proposal=dict(classes=('RESET','RESET'),demands=(0,)*20);valid=False
    error=not valid
   validation=tx.step(tlo,thi,tmsg,reset=reset)
   tx_ok=valid and validation['allowed'];error=bool(not reset and not tx_ok)
   credit_free=not any(proposal['demands'])
   r=rx.step(rlo,rhi,rmsg,receive=receive,send=send and tx_ok and not credit_free,demands=proposal['demands'],reset=reset)
   joint_rx=not reset and not rx.fatal and (not receive or r['rx_allowed'])
   r['tx_allowed']=bool(tx_ok and (joint_rx if credit_free else r['tx_allowed']))
   r['tx_taken']=bool(send and r['tx_allowed'])
   if r['tx_taken']:
    context.step(tlo,msg=messages);tx.step(tlo,thi,tmsg,transfer=True)
   proposal['classes']=tuple(next(k for k,v in C.items() if v==code) for code in validation['classes'])
   flags=pack([(r['rx_allowed'],1),(r['rx_taken'],1),(r['rx_rejected'],1),(r['tx_allowed'] and valid,1),(r['tx_taken'],1),(error,1),(r['classes'][0],3),(r['classes'][1],3),(C[proposal['classes'][0]],3),(C[proposal['classes'][1]],3),(r['init_repeat'],1),(r['init_conflict'],1)])
   meta=sum((t.slot|(int(t.reserve)<<5))<<(6*i) for i,t in enumerate(context.pending));be=sum((t.kind=='B')<<i for i,t in enumerate(context.pending));st=pack([(len(rx.sequence.pending),7),(sum((t=='B')<<i for i,t in enumerate(rx.sequence.pending)),73),(rx.budget.available[0],3),(rx.budget.available[1],4),(rx.fatal,1),(rx.content.open,1),(rx.content.poison,1),(slots(rx.ledger.capacity,width+1),20*(width+1)),(slots(rx.ledger.available,width+1),20*(width+1)),(rx.ledger.done,1),(rx.ledger.shared,1),(len(context.pending),7),(be,73),(meta,438),(len(tx.sequence.pending),7),(sum((x=='B')<<i for i,x in enumerate(tx.sequence.pending)),73),(tx.budget.available[0],3),(tx.budget.available[1],4),(False,1),(tx.content.open,1),(tx.content.poison,1)])
   rows.append(f'{int(not reset)} {int(receive)} {int(send)} {(rhi<<256)|rlo:x} {rmsg:x} {(thi<<256)|tlo:x} {tmsg:x} {flags:x} {slots(proposal["demands"],4):x} {st:x}')
   for k in ('rx_taken','rx_rejected','tx_taken'):coverage[k]+=int(r[k])
   coverage['tx_wait']+=int(send and not r['tx_taken']);coverage['context_error']+=int(error);coverage['rx_error_with_send']+=int(send and r['rx_rejected']);max_pending=max(max_pending,len(context.pending))
  def initialize(shared=False):
   emit(reset=True)
   for lane in range(5):emit(fc(lane),receive=True)
   emit(rhi=1|(int(shared)<<8),rmsg=2,receive=True)
  for k in (1,2,3,4,5):
   for vc in range(4):
    for pool in (0,1):
     initialize(shared=bool(vc%2));word=field(k,vc,pool,3 if k!=4 else 0);emit(tlo=word);emit(tlo=word,send=True)
     while context.pending:emit(send=True)
  # Actual init on the same clock as a send still cannot spend newly issued credit.
  emit(reset=True);emit(fc(0),1,2,field(1,0,1),receive=True,send=True);emit(tlo=field(1,0,1),send=True)
  # Bad incoming Message atomically stops an otherwise eligible continuation, then fatal stays sticky.
  emit(rhi=255,rmsg=2,receive=True,send=True);emit(receive=True,send=True);emit(reset=True)
  initialize();dense=sum(field(5,i%4,i%2,3)<<(32*i) for i in range(4 if auth else 8));emit(tlo=dense,send=True)
  for _ in range(40):emit(send=True)
  # Bootstrap flits need no peer credit. Invalid Rx still blocks that path.
  emit(reset=True);emit(tlo=fc(0),send=True);emit(thi=1,tmsg=2,send=True)
  emit(rhi=255,rmsg=2,tlo=fc(0),receive=True,send=True);emit(tlo=fc(0),send=True)
  # Mandatory NOP payload, poison pairing, unused AuthTag lanes and response budget.
  initialize();emit(thi=1,send=True);emit(send=True)
  emit(tlo=field(1,0,1),send=True);emit(thi=32,tmsg=2,send=True)
  for _ in range(4):emit(send=True)
  initialize();emit(tlo=field(4,0,1),thi=1<<255,send=True);emit(tlo=field(4,0,1),send=True)
  for _ in range(3):emit(send=True)
  initialize();many=sum(((5<<28)|(1<<14))<<(32*i) for i in range(4 if auth else 8));emit(tlo=many,send=True);emit(tlo=many,send=True)
  rng=random.Random(2920+width+auth)
  for i in range(2400):
   if i%67==0:initialize(shared=bool(i%2))
   k=rng.choice((1,2,3,4,5));tlo=field(k,rng.randrange(4),rng.randrange(2),rng.randrange(4) if k!=4 else 0)
   if len(context.pending)>1:tlo=rng.getrandbits(256)
   thi=0;tmsg=0
   if i%7==0:thi=rng.choice((0,1,32,255));tmsg=2
   rlo=rng.choice((0,0,0,fc(rng.randrange(5),1,1),field(4,0,1),6<<28));rhi=0;rmsg=0
   if i%11==0:rhi=rng.choice((0,1,257,32,255));rmsg=2
   emit(rlo,rhi,rmsg,tlo,thi,tmsg,receive=bool(rng.randrange(2)),send=bool(rng.randrange(3)))
  sim=S/'sim'/f'{width}_{auth}';sim.mkdir(parents=True,exist_ok=True);(sim/'vectors.txt').write_text('\n'.join(rows)+'\n');N=700+40*(width+1)
  tb=f'''`timescale 1ns/1ps // 时间单位
module tb; // 实际双向端口差分
reg clk=0;always #5 clk=~clk; // 唯一时钟
reg rstn=0,receive=0,send=0;reg [511:0] rflit=0,tflit=0;reg [1:0] rmsg=0,tmsg=0; // 实际输入
wire ra,rt,rr,ta,tt,ce,fatal,opened,poison,done,shared,repeat_init,conflict;wire [2:0] rl,rh,tl,th,rq;wire [3:0] rs;wire [6:0] rp,tp;wire [72:0] rb,tbmask;wire [437:0] metadata;wire [79:0] demands;wire [89:0] tx_state;wire [{20*(width+1)-1}:0] cap,avail; // 全部观察
 tl_credit_port #(.WIDTH({width})) dut(clk,rstn,receive,send,1'b{auth},rflit,rmsg,tflit,tmsg,ra,rt,rr,ta,tt,ce,rl,rh,tl,th,demands,rp,rb,rq,rs,fatal,opened,poison,cap,avail,done,shared,repeat_init,conflict,tp,tbmask,metadata,tx_state); // 实际顶层
integer fd,rc,n=0,r,v,s;reg [511:0] rf,tf;reg [1:0] rm,tm;reg [19:0] flags;reg [79:0] demand;reg [{N-1}:0] state;reg [4095:0] path; // 向量字段
initial begin // 自检
if(!$value$plusargs("vectors=%s",path))$fatal(1,"vectors");fd=$fopen(path,"r");if(!fd)$fatal(1,"open"); // 打开向量
while(!$feof(fd))begin // 遍历
rc=$fscanf(fd,"%d %d %d %h %h %h %h %h %h %h\\n",r,v,s,rf,rm,tf,tm,flags,demand,state);if(rc!=10)$fatal(1,"row"); // 完整解析
@(negedge clk);rstn=r;receive=v;send=s;rflit=rf;rmsg=rm;tflit=tf;tmsg=tm;#1; // 组合提议
if({{ra,rt,rr,ta,tt,ce,rl,rh,tl,th,repeat_init,conflict}}!==flags||demands!==demand)$fatal(1,"proposal row %0d got %h expected %h",n,{{ra,rt,rr,ta,tt,ce,rl,rh,tl,th,repeat_init,conflict}},flags); // 需求及许可
@(posedge clk);#1;if({{rp,rb,rq,rs,fatal,opened,poison,cap,avail,done,shared,tp,tbmask,metadata,tx_state}}!==state)$fatal(1,"state row %0d",n);n=n+1; // 完整状态
end // 遍历结束
$display("PASS port width={width} auth={auth} edges=%0d",n);$finish; // 完成
end // 自检结束
endmodule // TB结束
''';(sim/'tb.v').write_text(tb);cmd=['iverilog','-g2005','-s','tb','-o',str(sim/(a.label+'.vvp')),str(rtl),*[str(p) for p in [p for p in sorted((R/'rtl/tl').glob('*.v')) if p.name not in ('tl_receive_storage.v','tl_receive_context.v','tl_credit_publish.v')] if p.name!='tl_credit_port.v'],str(sim/'tb.v')];x=subprocess.run(cmd,capture_output=True,text=True);(sim/(a.label+'_compile.log')).write_text(x.stdout+x.stderr);row=dict(width=width,auth=auth,edges=len(rows),coverage=coverage,max_pending=max_pending,compile_exit_status=x.returncode,passed=False)
  if x.returncode==0:
   x=subprocess.run(['vvp',str(sim/(a.label+'.vvp')),'+vectors='+str(sim/'vectors.txt')],capture_output=True,text=True,timeout=120);(sim/(a.label+'.log')).write_text(x.stdout+x.stderr);row.update(run_exit_status=x.returncode,passed=x.returncode==0 and f'PASS port width={width} auth={auth} edges={len(rows)}' in x.stdout);print(x.stdout,flush=True)
  results.append(row)
r=dict(results=results,passed=all(x['passed'] for x in results),edges=sum(x['edges'] for x in results));(S/(a.label+'.json')).write_text(json.dumps(r,indent=2)+'\n');print(r);raise SystemExit(0 if r['passed'] else 1)

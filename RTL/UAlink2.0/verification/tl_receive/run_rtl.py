"""Run python3 verification/tl_receive/run_rtl.py --kd28-root /path/to/authorized/repository.
Outputs per-depth/auth actual SRAM TB, vectors and terminal results. Next faults,
strict lint, synthesis, and independent archive audit. Existing runs are not overwritten.
"""
from pathlib import Path
import argparse,json,subprocess,sys,random,hashlib
R=Path(__file__).resolve().parents[2];D=R;S=R/'build/verification/tl_receive';S.mkdir(parents=True,exist_ok=True);sys.path.insert(0,str(R/'model/tl'))

from receive_context import ReceiveContext
from tx_validation import TxValidation,C
p=argparse.ArgumentParser();p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label',default='healthy');p.add_argument('--replace',type=Path);p.add_argument('--rtl-dir',type=Path,default=R/'rtl/tl');a=p.parse_args();results=[]
root=a.kd28_root;ext=[root/'Library/models/kd28/sram/rtl'/x for x in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[root/'Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v']
def pack(values,bits):return sum(int(v)<<(i*bits) for i,v in enumerate(values))
def states(c,v):
 meta=pack([t.slot|(int(t.reserve)<<5)|(int(t.release_data)<<6)|(int(t.release_cmd)<<7) for t in c.pending],8)
 cs=(len(c.pending)<<(73+584))|(pack([t.kind=='B' for t in c.pending],1)<<584)|meta
 vs=(len(v.sequence.pending)<<83)|(pack([t=='B' for t in v.sequence.pending],1)<<10)|(v.budget.available[0]<<7)|(v.budget.available[1]<<3)|(int(v.content.open)<<1)|int(v.content.poison)
 return cs,vs

def vectors(auth,depth):
 ctx=ReceiveContext(auth=bool(auth));v=TxValidation(bool(auth));rows=[];rng=random.Random(147+auth);coverage=dict(poison=0,message=0,byte_enable=0,old_tail_new=0,multi_fields=0);totaldem=[0]*20;totalrel=[0]*20
 def emit(lower=0,upper=0,msg=0):
  cs,vs=states(ctx,v);messages=tuple((w&255) if msg>>i&1 else None for i,w in enumerate((lower,upper)))
  r=ctx.step(lower,msg=messages,transfer=False);check=v.step(lower,upper,msg)
  if not check['allowed']:raise RuntimeError('illegal generated input '+str((auth,len(rows),hex(lower),hex(upper),msg,r)))
  if tuple(C[x] for x in r['classes'])!=check['classes']:raise RuntimeError('context/full classes')
  ctx.step(lower,msg=messages);v.step(lower,upper,msg,transfer=True)
  bits=lower|(upper<<256)|(msg<<512)|(pack(check['classes'],3)<<514)|(pack(r['releases'],4)<<520)|(pack(r['demands'],4)<<600)|(int(r['store'])<<680)|(vs<<681)|(cs<<771)
  rows.append(bits)
  for i in range(20):totaldem[i]+=r['demands'][i];totalrel[i]+=r['releases'][i]
  for x in r['classes']:
   if x=='POISON':coverage['poison']+=1
   if x=='BYTE_ENABLE':coverage['byte_enable']+=1
   if x=='MESSAGE':coverage['message']+=1
 def automatic(word=0,poison=False):
  preview=ctx.step(word,transfer=False);halves=[word,0];msg=0
  for h,k in enumerate(preview['classes']):
   if k in ('DATA','BYTE_ENABLE'):
    halves[h]=rng.getrandbits(256)
    if poison and k=='DATA':halves[h]=(halves[h]&~255)|32;msg|=1<<h
  emit(*halves,msg)
 # Exact full-buffer bypass scenario at all depths.
 for j in range(depth):automatic((1<<124)|(3<<118)|(1<<102))
 emit(0x410404);emit(0,1,2)
 for j in range(100):
  kind=j%5+1;lane=(j//5)%5;vc=max(lane-1,0);pool=int(lane==0);n=j%4
  if kind==1:word=(1<<124)|(0x23<<118)|(vc<<116)|(pool<<102)|n
  elif kind==2:word=(2<<60)|(vc<<58)|(pool<<46)|(n<<44)|(1<<37)
  elif kind==3:word=(3<<60)|(3<<57)|(vc<<55)|(pool<<41)|(n<<39)
  elif kind==4:word=(4<<28)|(vc<<26)|(pool<<14)
  else:word=(5<<28)|(vc<<26)|(pool<<14)|(n<<2)|2
  if j%10==0:
   # Two independent fields in one Control, including a data-bearing field.
   word|=((4<<28)|(1<<14))<<128;coverage['multi_fields']+=1
  automatic(word,poison=j%7==0)
  inserted=False
  while ctx.pending:
   if not auth and len(ctx.pending)==1 and j%9==0:
    # New header-only Request consumes a different CMD class beside old data tail.
    automatic((1<<124)|(3<<118)|(1<<116),poison=j%7==0);coverage['old_tail_new']+=1
   elif not inserted and j%8==0:
    if len(ctx.pending)>=2:
     low=rng.getrandbits(256)
     if j%7==0:low=(low&~255)|32
     emit(low,0,3 if j%7==0 else 2)
    else:emit(0,0,3)
    inserted=True
   else:automatic(poison=j%7==0)
  emit(0x410404)
 for _ in range(16):emit()
 if totaldem!=totalrel:raise RuntimeError('closed-stream release conservation')
 return rows,coverage,totaldem
for depth in (1,3,17):
 for auth in (0,1):
  B=S/'sim'/a.label/f'd{depth}_a{auth}';B.mkdir(parents=True,exist_ok=False);rows,coverage,credits=vectors(auth,depth);(B/'vectors.hex').write_text('\n'.join(f'{v:0359x}' for v in rows)+'\n');N=len(rows);cw=max(1,depth.bit_length())
  tb=f'''`timescale 1ns/1ps // 实际SRAM功能模型测试
module tb; // 保存完整600bit字并独立核对消费归还
reg clk=0;always #5 clk=~clk;reg rstn=0,valid=0,ready=0;reg [511:0] flit=0;reg [1:0] msg=0; // 单时钟输入
wire allowed,taken,rejected,fatal,store,rv,retired;wire [2:0] lo,hi;wire [79:0] demands,releases,rr;wire [511:0] rf;wire [1:0] rm;wire [5:0] rc;wire [{cw-1}:0] count;wire [663:0] cs;wire [89:0] vs; // 实际观察
wire [599:0] output_word={{rr,rc,rm,rf}}; // 仅观察真实保存字
 tl_receive_storage #(.DEPTH({depth})) dut(.i_clk(clk),.i_rstn(rstn),.i_valid(valid),.i_auth(1'b{auth}),.i_flit(flit),.i_msg(msg),.o_allowed(allowed),.o_taken(taken),.o_rejected(rejected),.o_fatal(fatal),.o_lower(lo),.o_upper(hi),.o_demands(demands),.o_proposed_releases(releases),.o_store(store),.i_read_ready(ready),.o_read_valid(rv),.o_read_flit(rf),.o_read_msg(rm),.o_read_classes(rc),.o_read_releases(rr),.o_retired(retired),.o_count(count),.o_context_state(cs),.o_validation_state(vs)); // 真实Flit解析和实际SRAM实例
reg [1434:0] vectors[0:{N-1}];reg [1434:0] row;reg [599:0] golden[0:{N-1}];integer credited[0:19],returned[0:19]; // 独立脚本与预期队列
integer phase,cycle,idx,qhead,qtail,qcount,slot,edges=0,writes=0,reads=0,waits=0,bypass=0,simul=0;reg accept,consume;reg [663:0] nextcs;reg [89:0] nextvs; // 实际握手计数
initial begin // 两epoch含满状态复位与完整排空
 $readmemh("{B}/vectors.hex",vectors);
 for(phase=0;phase<2;phase=phase+1)begin
  @(negedge clk);rstn=0;valid=0;ready=0;repeat(2)@(posedge clk);#1;
  if(cs!==0||vs!==90'd576||count!==0||rv||fatal)$fatal(1,"reset state/ownership");
  idx=0;qhead=0;qtail=0;qcount=0;for(slot=0;slot<20;slot=slot+1)begin credited[slot]=0;returned[slot]=0;end
  cycle=0;
  while(cycle<(phase==0?80:10000) && !(phase==1&&idx=={N}&&qcount==0))begin
   @(negedge clk);rstn=1;row=idx<{N}?vectors[idx]:1435'd0;flit=row[511:0];msg=row[513:512];valid=idx<{N}&&(cycle%7!=3);ready=cycle>=100&&(cycle%9<6);#1;
   if(fatal||rejected)$fatal(1,"unexpected receive error cycle %0d index %0d",cycle,idx);
   if(idx<{N} && (cs!==row[1434:771]||vs!==row[770:681]))$fatal(1,"context state before %0d",idx);
   if(idx<{N} && {{store,demands,releases,hi,lo}}!==row[680:514])$fatal(1,"proposal/release %0d",idx);
   if(count!==qcount||allowed!==(store?(qcount<{depth}):1'b1)||taken!==(valid&&allowed))$fatal(1,"old FIFO capacity/admission");
   if(rv && (qcount==0||output_word!==golden[qhead]))$fatal(1,"stored payload/release order head %0d",qhead);
   accept=taken;consume=retired;nextcs=cs;nextvs=vs;
   if(valid&&!taken)waits=waits+1;if(taken&&!store&&qcount=={depth})bypass=bypass+1;if(accept&&store&&consume)simul=simul+1;
   @(posedge clk);edges=edges+1;
   if(consume)begin qhead=qhead+1;qcount=qcount-1;reads=reads+1;for(slot=0;slot<20;slot=slot+1)returned[slot]=returned[slot]+{{28'd0,rr[slot*4+:4]}};end
   if(accept)begin
    if(store)begin golden[qtail]=row[599:0];qtail=qtail+1;qcount=qcount+1;writes=writes+1;end
    for(slot=0;slot<20;slot=slot+1)credited[slot]=credited[slot]+{{28'd0,demands[slot*4+:4]}};
    idx=idx+1;nextcs=idx<{N}?vectors[idx][1434:771]:664'd0;nextvs=idx<{N}?vectors[idx][770:681]:90'd576;
   end
   #1;if(cs!==nextcs||vs!==nextvs||count!==qcount)$fatal(1,"post-commit context/occupancy");cycle=cycle+1;
  end
  if(phase==0 && qcount!={depth})$fatal(1,"reset did not interrupt full storage");
  if(phase==1)begin
   if(cycle==10000||qcount!=0||idx!={N})$fatal(1,"drain timeout");
   for(slot=0;slot<20;slot=slot+1)if(credited[slot]!=returned[slot])$fatal(1,"retired credit conservation slot %0d",slot);
  end
 end
 @(negedge clk);valid=1;flit=512'd1<<256;msg=0;ready=0;#1;
 if(!rejected||taken)$fatal(1,"bad NOP not rejected");
 @(posedge clk);#1;if(!fatal||cs!==0||count!==0)$fatal(1,"bad NOP state mutation");
 @(negedge clk);flit=0;#1;if(taken||allowed||rv)$fatal(1,"sticky fatal");
 if(waits==0||bypass==0||({depth}>1&&simul==0))$fatal(1,"missing wait/bypass/concurrency");
 $display("PASS receive storage depth={depth} auth={auth} edges=%0d writes=%0d reads=%0d waits=%0d bypass=%0d simultaneous=%0d",edges,writes,reads,waits,bypass,simul);$finish;
end // 完整独立检查结束
endmodule // 测试结束
''';(B/'tb.v').write_text(tb)
  sources=sorted(a.rtl_dir.glob('*.v')) + [R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v']
  if a.replace:sources=[a.replace if x.name==a.replace.name else x for x in sources]
  cmd=['iverilog','-g2005','-s','tb','-o',str(B/'sim.vvp'),*[str(x) for x in sources+ext],str(B/'tb.v')];(B/'command.json').write_text(json.dumps(cmd,indent=2)+'\n');x=subprocess.run(cmd,capture_output=True,text=True);(B/'compile.log').write_text(x.stdout+x.stderr)
  row=dict(depth=depth,auth=auth,compile_exit_status=x.returncode,passed=False,vectors=N,coverage=coverage,total_credits=credits)
  if x.returncode==0:
   x=subprocess.run(['vvp',str(B/'sim.vvp')],capture_output=True,text=True,timeout=90);(B/'run.log').write_text(x.stdout+x.stderr);row.update(run_exit_status=x.returncode,passed=x.returncode==0 and 'PASS receive storage' in x.stdout);print(x.stdout,flush=True)
  else:print(x.stdout+x.stderr,flush=True)
  results.append(row);(S/(a.label+'.json')).write_text(json.dumps(dict(complete=len(results)==6 and all(x['passed'] for x in results),results=results,external={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in ext}),indent=2)+'\n')
raise SystemExit(0 if all(x['passed'] for x in results) else 1)

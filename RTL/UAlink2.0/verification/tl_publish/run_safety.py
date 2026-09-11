"""Run python3 verification/tl_publish/run_safety.py. Writes unrestricted two-step safety SAT results.
Properties cover reset, held offer, idle counters and release gating; not full
protocol/reference induction. Actual early-debit RTL must fail counter hold.
"""
from pathlib import Path
import json,subprocess
R=Path(__file__).resolve().parents[2];D=R;S=R/'build/verification/tl_publish';S.mkdir(parents=True,exist_ok=True);B=S/'safety';B.mkdir(exist_ok=False);results=[];negative=[]
for width in (1,16):
 P=20*(width+1);N=P+49;v=f'''module safety(input wire clk,rstn,start,shared,release_valid,send,input wire [{20*width-1}:0] cap,input wire [79:0] releases,output wire reset_ok,offer_hold_ok,counter_hold_ok,release_gate_ok);
wire sr,st,ce,rr,rt,valid,taken,complete,mode,active,done;wire [31:0] word;wire [{P-1}:0] pending;wire [{N-1}:0] state;
tl_credit_publish #(.WIDTH({width})) dut(clk,rstn,start,shared,cap,sr,st,ce,release_valid,releases,rr,rt,send,valid,taken,complete,mode,word,active,done,pending,state);
reg pr,pv,pt,pst,prt;reg [34:0] po;reg [{P-1}:0] pp;
always @(posedge clk)begin pr<=rstn;pv<=valid;pt<=taken;pst<=st;prt<=rt;po<={{valid,complete,mode,word}};pp<=pending;end
assign reset_ok=pr||(state=={N}'d0);
assign offer_hold_ok=!(pr&&rstn&&pv&&!pt)||({{valid,complete,mode,word}}==po);
assign counter_hold_ok=!(pr&&!pst&&!prt&&!pt)||(pending==pp);
assign release_gate_ok=!rt||done;
endmodule
''';tb=B/f'w{width}.v';tb.write_text(v)
 for prop in ('reset_ok','offer_hold_ok','counter_hold_ok','release_gate_ok'):
  ys=B/f'w{width}_{prop}.ys';ys.write_text(f'read_verilog {R}/rtl/tl/tl_credit_publish.v {tb}\nprep -top safety -flatten\nopt_clean\nsat -verify -seq 2 -prove-skip 1 -prove {prop} 1\n');cmd=['yosys','-Q','-T','-s',str(ys)]
  try:x=subprocess.run(cmd,capture_output=True,text=True,timeout=180);code,log=x.returncode,x.stdout+x.stderr
  except subprocess.TimeoutExpired as e:code,log=124,(e.stdout or b'').decode()+(e.stderr or b'').decode()
  ys.with_suffix('.log').write_text(log);r=dict(width=width,property=prop,exit_status=code,passed=code==0 and 'SAT proof finished - no model found: SUCCESS!' in log);results.append(r);print(r,flush=True)
 ys=B/f'w{width}_early_debit.ys';ys.write_text((B/f'w{width}_counter_hold_ok.ys').read_text().replace(str(R/'rtl/tl/tl_credit_publish.v'),str(S/'faults/early_debit/tl_credit_publish.v')));x=subprocess.run(['yosys','-Q','-T','-s',str(ys)],capture_output=True,text=True,timeout=180);log=x.stdout+x.stderr;ys.with_suffix('.log').write_text(log);negative.append(dict(width=width,exit_status=x.returncode,detected=x.returncode==1 and 'proof did fail' in log))
(B/'result.json').write_text(json.dumps(dict(complete=all(x['passed'] for x in results) and all(x['detected'] for x in negative),results=results,negative=negative),indent=2)+'\n')

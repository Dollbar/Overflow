"""Run python3 verification/tl_publish/run_checks.py after validated regression terminates.
Writes synthesis/lint and real fault runs reusing exact healthy vectors and TB.
Next actual TL receiver integration and independent evidence audit.
"""
from pathlib import Path
import json,subprocess,hashlib
R=Path(__file__).resolve().parents[2];D=R;S=R/'build/verification/tl_publish';S.mkdir(parents=True,exist_ok=True);rtl=R/'rtl/tl/tl_credit_publish.v';rows=[]
def run(cmd,p,timeout=180):
 try:r=subprocess.run(cmd,capture_output=True,text=True,timeout=timeout);status,log=r.returncode,r.stdout+r.stderr
 except subprocess.TimeoutExpired as e:status,log=124,(e.stdout or b'').decode()+(e.stderr or b'').decode()
 p.write_text(log);return status,log
for width in (1,3,8,16):
 status,log=run(['verilator','--lint-only','-Wall',f'-GWIDTH={width}',str(rtl)],S/f'lint_{width}.log');rows.append(dict(kind='lint',width=width,exit_status=status,passed=status==0 and '%Warning' not in log and '%Error' not in log))
for width in (1,16):
 ys=S/f'synth_{width}.ys';ys.write_text(f'read_verilog {rtl}\nchparam -set WIDTH {width} tl_credit_publish\nsynth -top tl_credit_publish -flatten -noabc\ncheck -assert\nwrite_json {S}/synth_{width}.json\nstat\n');status,log=run(['yosys','-Q','-T','-s',str(ys)],S/f'synth_{width}.log');row=dict(kind='synth',width=width,exit_status=status,passed=status==0)
 if status==0:
  m=json.loads((S/f'synth_{width}.json').read_text())['modules']['tl_credit_publish'];ff=[c for c in m['cells'].values() if 'DFF' in c['type'] or 'LATCH' in c['type']];row.update(cells=len(m['cells']),ff=sum(len(c['connections']['Q']) for c in ff),single_clock=all(c['connections'].get('C')==m['ports']['i_clk']['bits'] for c in ff),latches=any('LATCH' in c['type'] for c in ff));row['passed'] &= row['single_clock'] and not row['latches']
 rows.append(row);print(row,flush=True)
changes={
'early_debit':('sent_extended=(o_taken&&!r_complete','sent_extended=(r_valid&&!r_complete'),
'repeat_offer':("r_valid<=1'b0;r_complete<=1'b0;r_word<=32'd0; // 清除已发送提议", "r_valid<=r_valid;r_complete<=r_complete;r_word<=r_word; // 清除已发送提议"),
'drop_concurrent_release':('(o_release_taken?release_extended:', '(o_release_taken&&!o_taken?release_extended:'),
'wrong_vc':("chosen_lane[1:0]-2'd1",'chosen_lane[1:0]'),
'wrong_shared':('r_shared<=i_shared','r_shared<=!i_shared'),
'early_complete':('if(has_pending)begin','if(has_pending&&r_done)begin'),
'early_release':('o_release_ready=i_rstn&&r_done','o_release_ready=i_rstn&&r_active')}
base=rtl.read_text()
for name,(before,after) in changes.items():
 count=base.count(before)
 if count!=(2 if name=='wrong_vc' else 1):raise RuntimeError('fault anchor '+name)
 B=S/'faults'/name;B.mkdir(parents=True,exist_ok=False);source=B/'tl_credit_publish.v';source.write_text(base.replace(before,after));results=[]
 for width in (1,3,8,16):
  for shared in (0,1):
   out=B/f'w{width}_s{shared}';out.mkdir();tb=S/'sim/final'/out.name/'tb.v';cmd=['iverilog','-g2005','-s','tb','-o',str(out/'sim.vvp'),str(source),str(tb)];(out/'command.json').write_text(json.dumps(cmd,indent=2)+'\n');status,log=run(cmd,out/'compile.log');r=dict(width=width,shared=shared,compile_exit_status=status,detected=False)
   if status==0:
    status,log=run(['vvp',str(out/'sim.vvp')],out/'run.log',90);r.update(run_exit_status=status,detected=status==1 and 'FATAL:' in log and 'PASS publish' not in log)
   results.append(r)
 row=dict(kind='fault',name=name,before=before,after=after,occurrences=count,sha256=hashlib.sha256(source.read_bytes()).hexdigest(),results=results,passed=all(x['detected'] for x in results));rows.append(row);print(name,row['passed'],flush=True)
(S/'checks.json').write_text(json.dumps(dict(complete=all(x['passed'] for x in rows),results=rows),indent=2)+'\n')
raise SystemExit(0 if all(x['passed'] for x in rows) else 1)

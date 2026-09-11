"""Run python3 verification/tl_publish/run_reachable_safety.py after run_safety.py.
Proves valid=>active by reset base and one-step induction, then uses that certified
invariant for the original unmodified offer-hold property. Preserves initial failures.
"""
from pathlib import Path
import subprocess,json
R=Path(__file__).resolve().parents[2];S=R/'build/verification/tl_publish';B=S/'safety';results=[]
for width in (1,16):
 old=B/f'w{width}.v';p=B/f'w{width}_invariant.v';p.write_text(old.read_text().replace('output wire reset_ok,','output wire active_valid_ok,reset_ok,').replace('endmodule','assign active_valid_ok=!valid||active;\nendmodule'))
 original=(B/f'w{width}_offer_hold_ok.ys').read_text();prefix=original.split('sat -verify')[0].replace(str(old),str(p))
 for name,prop,condition in [('valid_active_base','active_valid_ok','-set-at 1 rstn 0'),('valid_active_step','active_valid_ok','-set-at 1 active_valid_ok 1'),('offer_hold_reachable','offer_hold_ok','-set-at 1 active_valid_ok 1')]:
  ys=B/f'w{width}_{name}.ys';ys.write_text(prefix+f'sat -verify -seq 2 -prove-skip 1 {condition} -prove {prop} 1\n');x=subprocess.run(['yosys','-Q','-T','-s',str(ys)],capture_output=True,text=True,timeout=180);log=x.stdout+x.stderr;ys.with_suffix('.log').write_text(log);row=dict(width=width,name=name,property=prop,condition=condition,exit_status=x.returncode,passed=x.returncode==0 and 'SAT proof finished - no model found: SUCCESS!' in log);results.append(row);print(row,flush=True)
(B/'reachable.json').write_text(json.dumps(dict(complete=all(x['passed'] for x in results),results=results),indent=2)+'\n')
raise SystemExit(0 if all(x['passed'] for x in results) else 1)

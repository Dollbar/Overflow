"""Run python3 from project root. Writes lint/synthesis inventory and actual wiring-fault results.
Next complete joint induction, actual receive-port connection, and mapped timing.
"""
from pathlib import Path
import json,subprocess,hashlib
R=Path(__file__).resolve().parents[2];D=R;S=R/'build/verification/tl_port';S.mkdir(parents=True,exist_ok=True);sources=[p for p in sorted((R/'rtl/tl').glob('*.v')) if p.name not in ('tl_credit_publish.v','tl_receive_storage.v','tl_receive_context.v')];rows=[]
for w in (8,16):
 cmd=['verilator','--lint-only','-Wall','--top-module','tl_credit_port',f'-GWIDTH={w}',*[str(p) for p in sources]];x=subprocess.run(cmd,capture_output=True,text=True);log=x.stdout+x.stderr;(S/f'lint_{w}.log').write_text(log);rows.append(dict(kind='lint',width=w,command=cmd,exit_status=x.returncode,passed=x.returncode==0 and '%Warning' not in log and '%Error' not in log))
 ys=S/f'synth_{w}.ys';ys.write_text('read_verilog '+' '.join(str(p) for p in sources)+f'\nchparam -set WIDTH {w} tl_credit_port\nsynth -top tl_credit_port -flatten -noabc\ncheck -assert\nwrite_json {S}/synth_{w}.json\nstat\n');cmd=['yosys','-Q','-T','-s',str(ys)]
 try:x=subprocess.run(cmd,capture_output=True,text=True,timeout=180);code,log=x.returncode,x.stdout+x.stderr
 except subprocess.TimeoutExpired as e:code,log=124,(e.stdout or b'').decode()+(e.stderr or b'').decode()
 (S/f'synth_{w}.log').write_text(log);row=dict(kind='synth',width=w,exit_status=code,passed=code==0)
 if code==0:
  m=json.loads((S/f'synth_{w}.json').read_text())['modules']['tl_credit_port'];ff=[c for c in m['cells'].values() if 'DFF' in c['type'] or 'LATCH' in c['type']];row.update(cells=len(m['cells']),state_bits=sum(len(c['connections']['Q']) for c in ff),single_clock=all(c['connections'].get('C')==m['ports']['i_clk']['bits'] for c in ff),latches=any('LATCH' in c['type'] for c in ff));row['passed'] &= row['single_clock'] and not row['latches']
 rows.append(row);print(row,flush=True)
rtl=R/'rtl/tl/tl_credit_port.v';t=rtl.read_text();changes={
'premature_context_commit':('u_context(i_clk,i_rstn,o_tx_taken,','u_context(i_clk,i_rstn,i_send,'),
'skip_full_validation':('wire tx_valid=context_allowed&&full_allowed;','wire tx_valid=context_allowed;'),
'premature_full_commit':('u_tx_validation(i_clk,i_rstn,o_tx_taken,','u_tx_validation(i_clk,i_rstn,i_send,'),
'blocked_bootstrap':('(credit_free?rx_joint:credit_allowed)','credit_allowed'),
'free_ignores_receive_stop':('(credit_free?rx_joint:credit_allowed)',"(credit_free?1'b1:credit_allowed)"),
'paid_ignores_credit':('(credit_free?rx_joint:credit_allowed)','rx_joint'),
'wrong_message_source':('i_rx_flit,i_rx_msg,extended_demands','i_rx_flit,i_tx_msg,extended_demands'),
'zero_demands':('i_rx_msg,extended_demands,o_rx_allowed',"i_rx_msg,{(20*WIDTH){1'b0}},o_rx_allowed")}

for name,(old,new) in changes.items():
 if t.count(old)!=1:raise RuntimeError('mutation anchor')
 p=S/(name+'.v');p.write_text(t.replace(old,new));cmd=['python3',str(S/'run_rtl.py'),'--rtl',str(p),'--label',name];x=subprocess.run(cmd,capture_output=True,text=True);(S/(name+'_runner.log')).write_text(x.stdout+x.stderr);r=json.loads((S/(name+'.json')).read_text());detected=x.returncode==1 and all(z['compile_exit_status']==0 and z.get('run_exit_status')==1 for z in r['results']);rows.append(dict(kind='fault',name=name,before=old,after=new,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),exit_status=x.returncode,passed=detected));print(name,detected,flush=True)
r=dict(results=rows,complete=all(x['passed'] for x in rows));(S/'checks.json').write_text(json.dumps(r,indent=2)+'\n');raise SystemExit(0 if r['complete'] else 1)

#!/usr/bin/env python3
"""Run scheduler candidate: python3 verification/ip_tops/run_switch_egress_scheduler.py --label NEW --faults.
Writes immutable sources, vectors, simulation/static logs and manifest in build/verification/ip_tops/switch_egress_scheduler/NEW.
Next: review candidate before physical-port integration; no capacity ownership added.
"""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--label',required=True);ap.add_argument('--faults',action='store_true');a=ap.parse_args()
 if not a.label or any(c not in '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-' for c in a.label):raise ValueError('safe label')
 out=ROOT/'build/verification/ip_tops/switch_egress_scheduler'/a.label;out.mkdir(parents=True,exist_ok=False);src=out/'sources';src.mkdir()
 for name,path in {'switch_egress_scheduler.v':ROOT/'rtl/switch/switch_egress_scheduler.v','tb.sv':HERE/'switch_egress_scheduler_tb.sv','reference.py':HERE/'switch_egress_scheduler_reference.py','run.py':Path(__file__).resolve(),'contract.md':ROOT/'docs/switch_egress_scheduler_contract.md'}.items():(src/name).write_bytes(path.read_bytes())
 sys.path.insert(0,str(src));from reference import vectors
 def cmd(args,folder,log):
  try:r=subprocess.run(list(map(str,args)),cwd=folder,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90);code=r.returncode;data=r.stdout
  except subprocess.TimeoutExpired as e:code=124;data=e.stdout or b''
  (folder/log).write_bytes(data);return {'command':list(map(str,args)),'exit':code}
 cases=[];statics=[]
 configs=[(1,1,8,1),(2,2,33,2),(4,4,544,3),(1,4,33,15)]
 def case(name,p,v,d,limit,mutation=None):
  folder=out/name;folder.mkdir();cov=vectors(folder/'vectors.txt',p,v,d,8,limit);rtl=src/'switch_egress_scheduler.v'
  if mutation:
   old,new=mutation;content=rtl.read_text()
   if content.count(old)!=1:raise ValueError('fault anchor '+name)
   rtl=folder/rtl.name;rtl.write_text(content.replace(old,new))
  c=cmd(['iverilog','-g2012','-s','tb',f'-Ptb.P={p}',f'-Ptb.V={v}',f'-Ptb.D={d}',f'-Ptb.LIMIT={limit}','-o',folder/'sim.vvp',src/'tb.sv',rtl],folder,'compile.log');entry={'name':name,'parameters':[p,v,d,limit],'coverage':cov,'mutation':mutation,'compile':c,'passed':False}
  if c['exit']==0:
   r=cmd(['vvp',folder/'sim.vvp'],folder,'run.log');log=(folder/'run.log').read_text();entry['run']=r;entry['passed']=(r['exit']==1 and 'SCHEDULER_MISMATCH' in log) if mutation else (r['exit']==0 and 'SCHEDULER_PASS' in log)
   if mutation:entry['first_mismatch']=log.splitlines()[0]
  cases.append(entry);print(name,entry['passed'],flush=True)
 for p,v,d,l in configs:case(f'p{p}_v{v}_limit{l}',p,v,d,l)
 if a.faults:
  faults={
   'strict_response':('!found_req||reg_rsp_run<C_LIMIT',"!found_req||1'b1"),
   'stuck_rr':("reg_rsp_next<=({30'd0,chosen_vc}==C_VCS-32'd1)?2'd0:chosen_vc+2'd1;","reg_rsp_next<=2'd0;"),
   'stall_unlocked':("reg_owned<=1'b1;reg_response<=chosen_response;reg_vc<=chosen_vc;","reg_owned<=i_ready[ge];reg_response<=chosen_response;reg_vc<=chosen_vc;"),
   'bubble_unlocked':('if(reg_owned)begin',"if(reg_owned&&i_valid[((reg_response?VCS:0)+{30'd0,reg_vc})*PORTS+ge])begin"),
   'ready_fanout':('o_selected[gs*PORTS+ge]&&i_ready[ge]',"i_rstn&&i_ready[ge]"),
   'payload_bit':("selected_valid?i_data[slot*DATA_WIDTH+:DATA_WIDTH]:", "selected_valid?(i_data[slot*DATA_WIDTH+:DATA_WIDTH]^{{(DATA_WIDTH-1){1'b0}},1'b1}):"),
   'early_last':('if(i_ready[ge]&&selected_last)begin','if(i_ready[ge])begin')}
  for name,mutation in faults.items():case(name,2,2,33,2,mutation)
 for p,v,d,l in configs:
  folder=out/f'static_p{p}_v{v}_l{l}';folder.mkdir();rtl=src/'switch_egress_scheduler.v'
  statics.append(cmd(['iverilog','-g2001','-s','switch_egress_scheduler',f'-Pswitch_egress_scheduler.PORTS={p}',f'-Pswitch_egress_scheduler.VCS={v}',f'-Pswitch_egress_scheduler.DATA_WIDTH={d}',f'-Pswitch_egress_scheduler.RSP_BURST_MAX={l}','-o',folder/'rtl.vvp',rtl],folder,'g2001.log'))
  statics.append(cmd(['verilator','--lint-only','-Wall','--top-module','switch_egress_scheduler',f'-GPORTS={p}',f'-GVCS={v}',f'-GDATA_WIDTH={d}',f'-GRSP_BURST_MAX={l}',rtl],folder,'lint.log'))
  ys=f'read_verilog {rtl}\nhierarchy -check -top switch_egress_scheduler -chparam PORTS {p} -chparam VCS {v} -chparam DATA_WIDTH {d} -chparam RSP_BURST_MAX {l}\nproc\nflatten\nopt\nmemory_map\nopt\ncheck -assert\nstat\n';(folder/'check.ys').write_text(ys);statics.append(cmd(['yosys','-Q','-T','-s',folder/'check.ys'],folder,'yosys.log'))
 bad=[]
 for limit in (0,16):
  folder=out/f'invalid_limit{limit}';folder.mkdir();r=cmd(['iverilog','-g2001','-s','switch_egress_scheduler',f'-Pswitch_egress_scheduler.RSP_BURST_MAX={limit}','-o',folder/'invalid.vvp',src/'switch_egress_scheduler.v'],folder,'compile.log');r['passed']=r['exit']!=0 and 'INVALID_SCHEDULER_PARAMETERS' in (folder/'compile.log').read_text();bad.append(r)
 result={'cases':cases,'static':statics,'invalid_parameters':bad,'passed':all(c['passed'] for c in cases+bad) and all(s['exit']==0 for s in statics)};(out/'summary.json').write_text(json.dumps(result,indent=2)+'\n');(out/'manifest.json').write_text(json.dumps({str(p.relative_to(out)):hashlib.sha256(p.read_bytes()).hexdigest() for p in out.rglob('*') if p.is_file()},indent=2)+'\n');print(out,result['passed']);return 0 if result['passed'] else 1
if __name__=='__main__':sys.exit(main())

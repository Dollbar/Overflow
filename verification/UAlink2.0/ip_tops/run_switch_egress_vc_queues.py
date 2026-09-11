#!/usr/bin/env python3
"""Run production VC queues: python3 verification/ip_tops/run_switch_egress_vc_queues.py --label NEW --faults.
Outputs build/verification/ip_tops/switch_egress_vc_queues/NEW with source snapshots/trace/check/static; next integrate the Switch ingress and physical egress scheduler.
"""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--label',required=True);ap.add_argument('--faults',action='store_true');a=ap.parse_args()
 if not a.label or any(c not in '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-' for c in a.label):raise ValueError('safe label')
 out=ROOT/'build/verification/ip_tops/switch_egress_vc_queues'/a.label;out.mkdir(parents=True,exist_ok=False);src=out/'sources';src.mkdir()
 inputs={'switch_egress_vc_queues.v':ROOT/'rtl/switch/switch_egress_vc_queues.v','tb.sv':HERE/'switch_egress_vc_queues_tb.sv','reference.py':HERE/'switch_egress_vc_queues_reference.py','run.py':Path(__file__),'contract.md':ROOT/'docs/switch_egress_vc_queues_contract.md','switch_credit_reservation.v':ROOT/'rtl/switch/switch_credit_reservation.v','switch_egress_packet_queue.v':ROOT/'rtl/switch/switch_egress_packet_queue.v','upli_receive_fifo.v':ROOT/'rtl/upli/upli_receive_fifo.v'}
 for n,q in inputs.items():(src/n).write_bytes(q.read_bytes())
 sys.path.insert(0,str(src));from reference import check
 def cmd(c,d,name):
  try:r=subprocess.run(list(map(str,c)),cwd=d,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120);code=r.returncode;log=r.stdout
  except subprocess.TimeoutExpired as e:code=124;log=e.stdout or b''
  (d/name).write_bytes(log);return {'command':list(map(str,c)),'exit':code}
 results=[];static=[];deps=[src/n for n in ('switch_credit_reservation.v','switch_egress_packet_queue.v','upli_receive_fifo.v')]
 configs=[(1,1,8,[1,2]),(2,2,33,[3,2,0,5,2,4,3,2]),(4,4,544,[2+(s%4) if s!=15 else 0 for s in range(32)])]
 def case(name,p,v,d,caps,mutation=None,bad=0):
  folder=out/name;folder.mkdir();rtl=src/'switch_egress_vc_queues.v'
  if mutation:
   old,new=mutation;s=rtl.read_text()
   if s.count(old)!=1:raise ValueError('fault anchor '+name)
   rtl=folder/rtl.name;rtl.write_text(s.replace(old,new))
  packed=sum(n<<(4*s) for s,n in enumerate(caps));c=cmd(['iverilog','-g2012','-s','tb',f'-Ptb.P={p}',f'-Ptb.V={v}',f'-Ptb.D={d}',f'-Ptb.BAD={bad}',f"-Ptb.CAPS={len(caps)*4}'h{packed:x}",'-o',folder/'sim.vvp',src/'tb.sv',rtl,*deps],folder,'compile.log');res={'name':name,'ports':p,'vcs':v,'width':d,'caps':caps,'mutation':mutation,'bad':bad,'compile':c};ok=False
  if c['exit']==0:
   r=cmd(['vvp',folder/'sim.vvp'],folder,'run.log');res['run']=r
   try:res['coverage']=check(folder/'trace.txt',p,v,4,d,8,caps,bad=bad);ok=r['exit']==0 and 'VC_QUEUE_RUN_DONE' in (folder/'run.log').read_text()
   except ValueError as e:res['error']=str(e)
   if mutation:ok=r['exit']==0 and 'VC_QUEUE_MISMATCH' in res.get('error','')
  res['passed']=ok;results.append(res);print(name,ok,res.get('error',''),flush=True)
 for p,v,d,caps in configs:case(f'p{p}_v{v}',p,v,d,caps)
 for bad in range(1,7):case(f'illegal_{bad}',2,2,33,configs[1][3],bad=bad)
 if a.faults:
  mutations={
   'class_alias':('(i_header_response[gs]==RESPONSE)',"(i_header_response[gs]==1'b0)"),
   'owner_live_domain':('(reg_domain[source_index]==DOMAIN)',"(({1'b0,i_header_vc[source_index*2+:2]}+(i_header_response[source_index]?C_VCS:3'd0))==DOMAIN)"),
   'early_source_release':('else if(i_body_valid[gs]&&o_body_ready[gs]&&i_body_last[gs])','else if(i_body_valid[gs]&&o_body_ready[gs])'),
   'payload_bit':('selected_data=i_body_data[source_index*DATA_WIDTH+:DATA_WIDTH];',"selected_data=i_body_data[source_index*DATA_WIDTH+:DATA_WIDTH]^{{(DATA_WIDTH-1){1'b0}},1'b1};"),
   'cross_domain_ready':('.i_ready(i_ready[gd*PORTS+:PORTS])','.i_ready(i_ready[0+:PORTS])')}
  for name,m in mutations.items():case(name,2,2,33,configs[1][3],m)
 for p,v,_,caps in configs:
  folder=out/f'static{p}';folder.mkdir();rtl=src/'switch_egress_vc_queues.v';static.append(cmd(['iverilog','-g2001','-s','switch_egress_vc_queues',f'-Pswitch_egress_vc_queues.PORTS={p}',f'-Pswitch_egress_vc_queues.VCS={v}',f'-Pswitch_egress_vc_queues.DATA_WIDTH=33','-o',folder/'rtl.vvp',rtl,*deps],folder,'g2001.log'))
  static.append(cmd(['verilator','--lint-only','-Wall','--top-module','switch_egress_vc_queues',f'-GPORTS={p}',f'-GVCS={v}','-GDATA_WIDTH=33',rtl,*deps],folder,'lint.log'))
  ys='read_verilog '+' '.join(str(q) for q in [rtl,*deps])+f'\nhierarchy -check -top switch_egress_vc_queues -chparam PORTS {p} -chparam VCS {v} -chparam DATA_WIDTH 33\nproc\nflatten\nopt\nmemory_map\nopt\ncheck -assert\nstat\n';(folder/'check.ys').write_text(ys);static.append(cmd(['yosys','-Q','-T','-s',folder/'check.ys'],folder,'yosys.log'))
 result={'cases':results,'static':static,'passed':all(c['passed'] for c in results) and all(s['exit']==0 for s in static)};(out/'summary.json').write_text(json.dumps(result,indent=2)+'\n');(out/'manifest.json').write_text(json.dumps({str(f.relative_to(out)):hashlib.sha256(f.read_bytes()).hexdigest() for f in out.rglob('*') if f.is_file()},indent=2)+'\n');print(out,result['passed']);return 0 if result['passed'] else 1
if __name__=='__main__':sys.exit(main())

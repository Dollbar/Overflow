#!/usr/bin/env python3
"""Run the production packet-queue RTL with an independent chronological oracle.
Command: python3 verification/ip_tops/run_switch_egress_packet_queue.py --label NEW --faults.
Outputs build/verification/ip_tops/switch_egress_packet_queue/NEW evidence; next integrate physical egress scheduling.
"""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--label',required=True);ap.add_argument('--faults',action='store_true');a=ap.parse_args()
 if not a.label or any(c not in '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-' for c in a.label):raise ValueError('safe label')
 out=ROOT/'build/verification/ip_tops/switch_egress_packet_queue'/a.label;out.mkdir(parents=True,exist_ok=False);src=out/'sources';src.mkdir()
 inputs={'switch_egress_packet_queue.v':ROOT/'rtl/switch/switch_egress_packet_queue.v','tb.sv':HERE/'switch_egress_packet_queue_tb.sv','reference.py':HERE/'switch_egress_packet_queue_reference.py','run.py':Path(__file__),'contract.md':ROOT/'docs/switch_egress_packet_queue_contract.md','integration_check.sv':HERE/'switch_egress_packet_queue_integration_check.sv','direct_tb.sv':HERE/'switch_egress_packet_queue_direct_tb.sv'}
 for n,path in inputs.items():(src/n).write_bytes(path.read_bytes())
 for n,sub in (('switch_credit_reservation.v','switch'),('upli_receive_fifo.v','upli')):(src/n).write_bytes((ROOT/'rtl'/sub/n).read_bytes())
 sys.path.insert(0,str(src));from reference import check
 def cmd(c,d,name):
  try:r=subprocess.run(list(map(str,c)),cwd=d,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120);code=r.returncode;log=r.stdout
  except subprocess.TimeoutExpired as e:code=124;log=e.stdout or b''
  (d/name).write_bytes(log);return {'command':list(map(str,c)),'exit':code}
 results=[];static=[]
 def case(name,p,d,caps,mutation=None,bad=0):
  folder=out/name;folder.mkdir();rtl=src/'switch_egress_packet_queue.v'
  if mutation:
   old,new=mutation;s=rtl.read_text()
   if s.count(old)!=1:raise ValueError('fault anchor '+name)
   rtl=folder/rtl.name;rtl.write_text(s.replace(old,new))
  packed=sum(n<<(4*e) for e,n in enumerate(caps));sources=[rtl,src/'switch_credit_reservation.v',src/'upli_receive_fifo.v']
  c=cmd(['iverilog','-g2012','-s','tb',f'-Ptb.P={p}',f'-Ptb.D={d}',f'-Ptb.BAD={bad}',f"-Ptb.CAPS={p*4}'h{packed:x}",'-o',folder/'sim.vvp',src/'tb.sv',*sources],folder,'compile.log');r=None;result={'name':name,'ports':p,'data_width':d,'caps':caps,'mutation':mutation,'illegal_input':bad,'compile':c}
  if c['exit']==0:
   r=cmd(['vvp',folder/'sim.vvp'],folder,'run.log');result['run']=r
   try:result['coverage']=check(folder/'trace.txt',p,4,d,8,caps,expect_bad=bool(bad));ok=r['exit']==0 and b'QUEUE_RUN_DONE' in (folder/'run.log').read_bytes()
   except ValueError as e:result['error']=str(e);ok=False
   if mutation:ok=r['exit']==0 and 'QUEUE_MISMATCH' in result.get('error','')
  else:ok=False
  result['passed']=ok;results.append(result);print(name,ok,result.get('error',''),flush=True)
 for p,d,caps in ((1,8,[1]),(1,544,[7]),(2,33,[3,7]),(4,544,[2,5,0,7])):case(f'p{p}_d{d}',p,d,caps)
 for bad in (1,2,3):case(f'illegal_{bad}',4,544,[2,5,0,7],bad=bad)
 if a.faults:
  mutations={
   'publish_partial':('(reg_complete!=0)&&fifo_valid','(reg_reserved!=0)&&fifo_valid'),
   'release_each_word':('assign retire=pop&&o_last[e];','assign retire=pop;'),
   'lose_last_word':('.i_write_valid(write_fire),','.i_write_valid(write_fire&&!finish),'),
   'live_token':('reg_units,reg_token,i_write_data','reg_units,i_write_token[e*TOKEN_WIDTH+:TOKEN_WIDTH]^{{(TOKEN_WIDTH-1){1\'b0}},1\'b1},i_write_data'),
   'payload_bit':('o_valid[e]?head[DATA_WIDTH-1:0]','o_valid[e]?(head[DATA_WIDTH-1:0]^{{(DATA_WIDTH-1){1\'b0}},1\'b1})'),
   'release_short':('assign o_release_units[e*UNIT_WIDTH+:UNIT_WIDTH]=retire?retired_units:',"assign o_release_units[e*UNIT_WIDTH+:UNIT_WIDTH]=retire?C_ONE:"),
   'double_charge':('reg_reserved+(reserve_fire?offered:', 'reg_reserved+(reserve_fire?C_ONE:')}
  for name,mutation in mutations.items():case(name,4,544,[2,5,0,7],mutation)
 folder=out/'direct';folder.mkdir();c=cmd(['iverilog','-g2012','-s','direct_tb','-o',folder/'sim.vvp',src/'direct_tb.sv',src/'switch_egress_packet_queue.v',src/'upli_receive_fifo.v'],folder,'compile.log');r=cmd(['vvp',folder/'sim.vvp'],folder,'run.log') if c['exit']==0 else {'exit':-1};results.append({'name':'direct_interface','compile':c,'run':r,'passed':c['exit']==0 and r['exit']==0 and 'DIRECT_QUEUE_PASS' in (folder/'run.log').read_text()})
 for p in (1,2,4):
  folder=out/f'static{p}';folder.mkdir();rtl=src/'switch_egress_packet_queue.v';fifo=src/'upli_receive_fifo.v'
  static.append(cmd(['iverilog','-g2001','-s','switch_egress_packet_queue',f'-Pswitch_egress_packet_queue.PORTS={p}','-o',folder/'rtl.vvp',rtl,fifo],folder,'g2001.log'))
  static.append(cmd(['verilator','--lint-only','-Wall','--top-module','switch_egress_packet_queue',f'-GPORTS={p}',rtl,fifo],folder,'lint.log'))
  ys=f'read_verilog {rtl} {fifo}\nhierarchy -check -top switch_egress_packet_queue -chparam PORTS {p}\nproc\nopt\nmemory_map\nopt\ncheck -assert\nstat\n';(folder/'check.ys').write_text(ys);static.append(cmd(['yosys','-Q','-T','-s',folder/'check.ys'],folder,'yosys.log'))
 folder=out/'integration';folder.mkdir();ys=f'read_verilog {src/"switch_egress_packet_queue.v"} {src/"upli_receive_fifo.v"} {src/"switch_credit_reservation.v"} {src/"integration_check.sv"}\nhierarchy -check -top integration_check\nproc\nflatten\nopt\nmemory_map\nopt\ncheck -assert\nstat\n';(folder/'check.ys').write_text(ys);static.append(cmd(['yosys','-Q','-T','-s',folder/'check.ys'],folder,'yosys.log'))
 summary={'cases':results,'static':static,'passed':all(r['passed'] for r in results) and all(s['exit']==0 for s in static)};(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');(out/'manifest.json').write_text(json.dumps({str(f.relative_to(out)):hashlib.sha256(f.read_bytes()).hexdigest() for f in out.rglob('*') if f.is_file()},indent=2)+'\n');print(out,summary['passed']);return 0 if summary['passed'] else 1
if __name__=='__main__':sys.exit(main())

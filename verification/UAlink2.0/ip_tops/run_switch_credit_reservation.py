#!/usr/bin/env python3
"""Production-layout: python3 verification/ip_tops/run_switch_credit_reservation.py --label NEW --faults.
Outputs results/NEW/{sources,vectors,logs,summary,manifest}; next integrate actual egress queue.
"""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())

def main():
 a=argparse.ArgumentParser(description=__doc__);a.add_argument('--label',required=True);a.add_argument('--faults',action='store_true');args=a.parse_args()
 if not args.label or any(c not in '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-' for c in args.label):raise ValueError('safe label')
 out=ROOT/'build/verification/ip_tops/switch_credit_reservation'/args.label;out.mkdir(parents=True,exist_ok=False);src=out/'sources';src.mkdir()
 for n,origin in (('switch_credit_reservation.v',ROOT/'rtl/switch/switch_credit_reservation.v'),('reference.py',HERE/'switch_credit_reservation_reference.py'),('tb.sv',HERE/'switch_credit_reservation_tb.sv'),('run.py',Path(__file__).resolve()),('contract.md',ROOT/'docs/switch_credit_reservation_review.md')):(src/n).write_bytes(origin.read_bytes())
 sys.path.insert(0,str(src));from reference import vectors
 results=[]
 def cmd(c,cwd,name):
  try:p=subprocess.run(c,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90);code=p.returncode;log=p.stdout
  except subprocess.TimeoutExpired as e:code=124;log=e.stdout or b''
  (cwd/name).write_bytes(log);return {'command':list(map(str,c)),'exit':code}
 def case(name,p,w,caps,mutation=None):
  d=out/name;d.mkdir();rows,cov=vectors(p,w,caps);(d/'vectors.txt').write_text(''.join(' '.join(f'{v:x}' for v in row)+'\n' for row in rows));(d/'coverage.json').write_text(json.dumps(cov,indent=2)+'\n');rtl=src/'switch_credit_reservation.v'
  if mutation:
   old,new=mutation;s=rtl.read_text()
   if s.count(old)!=1:raise ValueError('fault anchor '+name)
   rtl=d/rtl.name;rtl.write_text(s.replace(old,new))
  packed=sum(c<<(e*w) for e,c in enumerate(caps));c=cmd(['iverilog','-g2012','-s','tb',f'-Ptb.PORTS={p}',f'-Ptb.W={w}',f"-Ptb.CAPS={p*w}'h{packed:x}",'-o',str(d/'sim.vvp'),str(src/'tb.sv'),str(rtl)],d,'compile.log');r=cmd(['vvp',str(d/'sim.vvp')],d,'run.log') if c['exit']==0 else None
  ok=c['exit']==0 and r is not None and ((r['exit']!=0 and 'RESERVATION_MISMATCH' in (d/'run.log').read_text()) if mutation else (r['exit']==0 and 'RESERVATION_PASS' in (d/'run.log').read_text()))
  results.append(dict(name=name,ports=p,width=w,caps=caps,cycles=len(rows),mutation=mutation,compile=c,run=r,passed=ok));print(name,ok,flush=True)
 for p,w,caps in ((1,3,[5]),(2,4,[3,5]),(4,4,[2,5,0,7]),(4,16,[65535,257,4,0])):case(f'p{p}_w{w}',p,w,caps)
 if args.faults:
  mutations={
   'rr_stuck':("reg_next <= selected_index + {{(INDEX_WIDTH-1){1'b0}},1'b1};","reg_next <= reg_next;"),
   'first_unit_only':('accepted ? selected_units : {UNIT_WIDTH{1\'b0}}','accepted ? {{(UNIT_WIDTH-1){1\'b0}},1\'b1} : {UNIT_WIDTH{1\'b0}}'),
   'ready_bypass':('i_rstn && i_admit_ready[ge] &&','i_rstn &&'),
   'current_return_bypass':('<= reg_available);','<= (reg_available + released));'),
   'release_oversubscribe':('(released > used)','1\'b0'),
   'transpose_route':('i_route_match[gs*PORTS+ge]','i_route_match[ge*PORTS+gs]')}
  for name,mutation in mutations.items():case(name,4,4,[2,5,0,7],mutation)
 static=[]
 for p in (1,2,4):
  d=out/f'static{p}';d.mkdir();rtl=src/'switch_credit_reservation.v'
  static.append(cmd(['iverilog','-g2001','-s','switch_credit_reservation',f'-Pswitch_credit_reservation.PORTS={p}','-o',str(d/'rtl.vvp'),str(rtl)],d,'g2001.log'))
  static.append(cmd(['verilator','--lint-only','-Wall','--top-module','switch_credit_reservation',f'-GPORTS={p}',str(rtl)],d,'lint.log'))
  script=f'read_verilog {rtl}\nhierarchy -check -top switch_credit_reservation -chparam PORTS {p}\nproc\nopt\nmemory_map\nopt\ncheck -assert\nstat\n';(d/'check.ys').write_text(script);static.append(cmd(['yosys','-Q','-T','-s',str(d/'check.ys')],d,'yosys.log'))
 result={'cases':results,'static':static,'passed':all(c['passed'] for c in results) and all(c['exit']==0 for c in static)};(out/'summary.json').write_text(json.dumps(result,indent=2)+'\n');(out/'manifest.json').write_text(json.dumps({str(f.relative_to(out)):hashlib.sha256(f.read_bytes()).hexdigest() for f in out.rglob('*') if f.is_file()},indent=2)+'\n');print(out,result['passed']);return 0 if result['passed'] else 1
if __name__=='__main__':sys.exit(main())

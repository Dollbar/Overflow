#!/usr/bin/env python3
"""Check legacy candidate against published switch TB; writes fresh results/legacy_LABEL.
Run python3 verification/ip_tops/run_switch_egress_typed_legacy.py --label NEW --baseline OLD_TOP.
Next review compatibility, not a formal equivalence claim.
"""
from pathlib import Path
import argparse,importlib.util,json,hashlib,subprocess
B=Path(__file__).resolve().parent;ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
a=argparse.ArgumentParser(description=__doc__);a.add_argument('--label',required=True);a.add_argument('--baseline',type=Path,required=True);a=a.parse_args()
if not a.label or any(c not in '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-' for c in a.label):raise ValueError('safe label')
out=ROOT/'build/verification/ip_tops/switch_egress_typed_legacy'/a.label;out.mkdir(parents=True,exist_ok=False);src=out/'source';src.mkdir()
spec=importlib.util.spec_from_file_location('baseline',ROOT/'verification/ip_tops/run_switch.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);(src/'switch_tb.sv').write_text(m.TB)
inv=json.loads((ROOT/'config/ip_module_inventory.json').read_text());paths=[ROOT/'rtl/switch'/n for n in ('switch_route_lookup.v','switch_route_table.v','switch_arbiter.v','switch_fabric.v')]+list((ROOT/'rtl/scaffold').rglob('*switch*.v'))+[ROOT/e['path'] for e in inv['modules'] if e['status']=='planned' and 'switch' in e['roles']]
for p in paths:(src/p.name).write_bytes(p.read_bytes())
for kind,p in [('baseline',a.baseline.resolve()),('candidate',ROOT/'rtl/switch/ualink_switch_top.v')]:(src/(kind+'.v')).write_bytes(p.read_bytes())
(src/'run_legacy.py').write_bytes(Path(__file__).read_bytes())
files=[src/p.name for p in paths]
waiver=src/'scaffold.vlt';lines=['`verilator_config']+[f'lint_off -rule UNUSEDSIGNAL -file "{src/Path(e["path"]).name}"' for e in inv['modules'] if e['status']=='planned' and 'switch' in e['roles']]+[f'lint_off -rule {rule} -file "{src/"ualink_switch_scaffold.v"}"' for rule in ('UNUSEDSIGNAL','PINCONNECTEMPTY')];waiver.write_text('\n'.join(lines)+'\n')
def cmd(c,d,log):
 r=subprocess.run(list(map(str,c)),cwd=d,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60);(d/log).write_bytes(r.stdout);return {'command':list(map(str,c)),'exit':r.returncode}
rows=[]
for ports in (1,2,4):
 for kind in ('baseline','candidate'):
  d=out/f'p{ports}_{kind}';d.mkdir();rtl=src/(kind+'.v');commands={}
  if ports>1:
   commands['compile']=cmd(['iverilog','-g2012','-s','switch_tb',f'-Pswitch_tb.PORTS={ports}','-o',d/'sim.vvp',src/'switch_tb.sv',rtl,*files],d,'compile.log')
   if commands['compile']['exit']==0:commands['run']=cmd(['vvp',d/'sim.vvp'],d,'run.log')
  if kind=='candidate':
   commands['g2001']=cmd(['iverilog','-g2001','-s','ualink_switch_top',f'-Pualink_switch_top.PORTS={ports}','-o',d/'rtl.vvp',rtl,*files],d,'g2001.log')
   # Filename substitution for the candidate snapshot avoids an artificial DECLFILENAME warning.
   named=d/'ualink_switch_top.v';named.write_bytes(rtl.read_bytes())
   commands['lint']=cmd(['verilator','--lint-only','--language','1364-2001','-Wall','--top-module','ualink_switch_top',f'-GPORTS={ports}',waiver,named,*files],d,'lint.log')
   commands['yosys']=cmd(['yosys','-Q','-T','-p','read_verilog '+' '.join(map(str,[rtl,*files]))+f'; hierarchy -check -top ualink_switch_top -chparam PORTS {ports}; proc; opt; check -assert; stat'],d,'yosys.log')
  passed=all(r['exit']==0 for r in commands.values()) and (ports==1 or 'PASS ' in (d/'run.log').read_text());rows.append({'ports':ports,'kind':kind,'passed':passed,'commands':commands});print(ports,kind,passed,flush=True)
for ports in (2,4):
 logs=[(out/f'p{ports}_{k}'/'run.log').read_text() for k in ('baseline','candidate')]
 lines=[[x for x in log.splitlines() if x.startswith('PASS')] for log in logs]
 if lines[0]!=lines[1]:raise ValueError('different legacy public coverage')
j={'passed':all(r['passed'] for r in rows),'cases':rows,'legacy_pass_lines_equal':True,'artifacts_sha256':{str(p.relative_to(out)):hashlib.sha256(p.read_bytes()).hexdigest() for p in out.rglob('*') if p.is_file()}};(out/'result.json').write_text(json.dumps(j,indent=2)+'\n');raise SystemExit(0 if j['passed'] else 1)

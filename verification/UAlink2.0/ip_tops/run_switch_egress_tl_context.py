#!/usr/bin/env python3
"""Run full-record/context matrix against snapshotted actual TL RTL and independent model."""
import argparse,hashlib,importlib.util,json,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
OUT=ROOT/'build/verification/ip_tops/switch_egress_tl_context'
RTL=ROOT/'rtl/switch/switch_egress_tl_context.v'
TB=HERE/'switch_egress_tl_context_tb.sv'
REF=HERE/'switch_egress_tl_context_reference.py'
DEPS=['rtl/tl/'+n+'.v' for n in ('tl_receive_context','tl_sequence','tl_control_tenure','tl_control_decode')]
MODELS=['model/tl/'+n+'.py' for n in ('receive_context','credit_context','tl_sequence','tl_tenure')]
def sha(b):return hashlib.sha256(b).hexdigest()
def run(cmd,path,name):
 try:r=subprocess.run(cmd,cwd=path,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120);code=r.returncode;data=r.stdout
 except subprocess.TimeoutExpired as e:code=124;data=(e.stdout or b'')+b'\nTIMEOUT\n'
 (path/(name+'.log')).write_bytes(data);return code
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--label',required=True);ap.add_argument('--faults',action='store_true');a=ap.parse_args()
 if Path(a.label).name!=a.label:raise ValueError('label must be a single component')
 out=OUT/a.label;out.mkdir(parents=True,exist_ok=False);src=out/'sources';src.mkdir();sources={}
 for f in [RTL,TB,REF,Path(__file__).resolve()]+[ROOT/p for p in DEPS+MODELS]:
  blob=f.read_bytes();target=src/f.name
  if target.exists():raise ValueError('snapshot basename collision')
  target.write_bytes(blob);sources[str(f)]=sha(blob)
 sys.path.insert(0,str(src));spec=importlib.util.spec_from_file_location('oracle',src/REF.name);oracle=importlib.util.module_from_spec(spec);spec.loader.exec_module(oracle)
 dut=src/RTL.name;deps=[str(src/Path(f).name) for f in DEPS];text=dut.read_text();cases=[]
 specs=[(p,v,None) for p in (1,2,4) for v in (1,2,4)]
 faults={
 'commit_stall':('.i_commit(o_captured[p])','.i_commit(i_valid[p])'),
 'class_swap':('reg_classes<= {ctx_upper,ctx_lower}','reg_classes<= {ctx_lower,ctx_upper}'),
 'metadata_loss':('reg_metadata_before<= ctx_metadata','reg_metadata_before<= 584\'b0'),
 'auth_bypass':('.i_auth(i_auth[p])',".i_auth(1'b0)"),
 'record_high_loss':('reg_record<= i_record[p*544+:544]',"reg_record<= {1'b0,i_record[p*544+:543]}"),
 'overwrite':('(!reg_valid||i_ready[p])',"1'b1")}
 if a.faults:specs += [(2,2,k) for k in faults]
 for p,v,fault in specs:
  case=out/(fault or f'p{p}_v{v}');case.mkdir();coverage=oracle.vectors(case/'vectors.txt',p,v,8);current=dut
  if fault:
   old,new=faults[fault]
   if text.count(old)!=1:raise ValueError('fault anchor '+fault)
   current=case/RTL.name;current.write_text(text.replace(old,new))
  files=[str(current)]+deps
  compile_code=run(['iverilog','-g2012','-s','tb',f'-Ptb.P={p}',f'-Ptb.V={v}','-o','sim.vvp',str(src/TB.name)]+files,case,'compile')
  sim=run(['vvp','sim.vvp'],case,'run') if compile_code==0 else None
  row=dict(name=case.name,ports=p,vcs=v,fault=fault,compile=compile_code,run=sim,coverage=coverage,static={})
  if not fault:
   row['static']['g2001']=run(['iverilog','-g2001','-s','switch_egress_tl_context',f'-Pswitch_egress_tl_context.PORTS={p}',f'-Pswitch_egress_tl_context.VCS={v}','-o','leaf.vvp']+files,case,'g2001')
   row['static']['lint']=run(['verilator','--lint-only','-Wall','--top-module','switch_egress_tl_context',f'-GPORTS={p}',f'-GVCS={v}']+files,case,'lint')
   script='read_verilog '+ ' '.join(files)+f'\nhierarchy -check -top switch_egress_tl_context -chparam PORTS {p} -chparam VCS {v}\nproc\nopt\ncheck -assert\nstat\n';(case/'synth.ys').write_text(script)
   row['static']['yosys']=run(['yosys','-s','synth.ys'],case,'yosys')
  row['passed']=compile_code==0 and ((sim!=0 and sim is not None and 'CONTEXT_MISMATCH' in (case/'run.log').read_text()) if fault else sim==0 and all(x==0 for x in row['static'].values()))
  cases.append(row);print(case.name,row['passed'],row['static'],flush=True)
 result=dict(passed=all(x['passed'] for x in cases),sources=sources,cases=cases,prepared_reconstruction=False,actual_tl_send=False,dl_attachment=False)
 (out/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
 artifacts={str(f.relative_to(out)):sha(f.read_bytes()) for f in sorted(out.rglob('*')) if f.is_file() and '__pycache__' not in f.parts};(out/'artifacts.json').write_text(json.dumps(artifacts,indent=2)+'\n')
 return 0 if result['passed'] else 1
if __name__=='__main__':sys.exit(main())

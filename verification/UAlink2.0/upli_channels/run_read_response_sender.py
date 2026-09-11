#!/usr/bin/env python3
"""Run: python3 verification/upli_channels/run_read_response_sender.py --label NEW --faults.
Outputs fresh build/verification/upli_channels/read_response_sender/NEW snapshots, vectors, logs, summary and manifest.
Next connect verified native response events to station/Endpoint adapters; this is not RX or RAS recovery.
"""
import argparse,hashlib,json,subprocess,sys,time
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
RTL=ROOT/'rtl/upli/upli_read_response_sender.v'
TB=HERE/'read_response_sender_tb.sv'
OUT=ROOT/'build/verification/upli_channels/read_response_sender'
sys.path.insert(0,str(HERE))

def sha(blob):return hashlib.sha256(blob).hexdigest()
def command(cmd,cwd,log,timeout=100):
 t=time.monotonic()
 try:
  p=subprocess.run(cmd,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout);rc=p.returncode;out=p.stdout
 except subprocess.TimeoutExpired as e:rc=124;out=(e.stdout or b'')+b'\nTIMEOUT\n'
 (cwd/log).write_bytes(out);return {'command':list(map(str,cmd)),'exit':rc,'seconds':time.monotonic()-t,'log':log}
def main():
 a=argparse.ArgumentParser();a.add_argument('--label',required=True);a.add_argument('--faults',action='store_true');args=a.parse_args()
 if not args.label or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in args.label):raise ValueError('unsafe label')
 out=OUT/args.label;out.mkdir(parents=True,exist_ok=False);src=out/'sources';src.mkdir()
 inputs=[RTL,ROOT/'rtl/upli/upli_credit_bank.v',ROOT/'rtl/upli/upli_read_response_channel.v',ROOT/'rtl/upli/upli_parity.v',TB,HERE/'read_response_sender_reference.py',HERE/'read_response_sender_vectors.py',Path(__file__)]
 sources={}
 for p in inputs:
  blob=p.read_bytes();(src/p.name).write_bytes(blob);sources[str(p)]=sha(blob)
 sys.path.insert(0,str(src))
 from read_response_sender_vectors import generate
 dependencies=[src/p.name for p in inputs[:4]];tb=src/TB.name;results=[]
 def run_case(name,ports,width=4,mutation=None):
  case=out/name;case.mkdir();rows,cov=generate(ports,width);(case/'vectors.txt').write_text(''.join(' '.join(format(x,'x') for x in row)+'\n' for row in rows));(case/'coverage.json').write_text(json.dumps(cov,indent=2)+'\n')
  deps=dependencies[:]
  if mutation:
   original=deps[0].read_text();old,new=mutation
   if original.count(old)!=1:raise ValueError('fault anchor '+name)
   modified=case/RTL.name;modified.write_text(original.replace(old,new));deps[0]=modified
  c=command(['iverilog','-g2012','-s','tb',f'-Ptb.PORTS={ports}',f'-Ptb.CW={width}','-o',str(case/'sim.vvp'),str(tb),*map(str,deps)],case,'compile.log')
  r=command(['vvp',str(case/'sim.vvp')],case,'run.log') if c['exit']==0 else None
  good=c['exit']==0 and r is not None and ((r['exit']==0 and 'READ_SENDER_PASS' in (case/'run.log').read_text()) if not mutation else (r['exit']!=0 and 'READ_SENDER_MISMATCH' in (case/'run.log').read_text()))
  results.append(dict(name=name,ports=ports,width=width,rows=len(rows),mutation=mutation,compile=c,run=r,passed=good));print(name,good,flush=True)
 for p,w in ((1,3),(2,4),(4,4),(4,8)):run_case(f'ports{p}_cw{w}',p,w)
 if args.faults:
  faults={
   'tail_candidate':('reg_pools[reg_index],tail_word}','reg_pools[reg_index],i_candidate_payload[618:0]}'),
   'first_only_debit':('.i_send_valid(o_valid)','.i_send_valid(o_candidate_accepted)'),
   'idle_phase_freeze':('end else if (reg_tdm_known) begin','end else if (reg_tdm_known && raw_valid) begin'),
   'short_reservation':('&& flag_enough;','&& 1\'b1;'),
   'wrong_tail_pool':('reg_pools[reg_index],tail_word}','reg_pools[0],tail_word}'),
   'src_overconstraint':("&& (word_fields[9:6] == i_candidate_payload[9:6])","&& (word_fields[554:545] == i_candidate_payload[554:545]) && (word_fields[9:6] == i_candidate_payload[9:6])"),
   'single_last_required':('(candidate_num == 2\'d0) || !flag_declared','((candidate_num == 2\'d0) && i_candidate_payload[3]) || !flag_declared')}
  for name,mutation in faults.items():run_case(name,4,mutation=mutation)
 static=[]
 for p in (1,2,4):
  case=out/f'static{p}';case.mkdir()
  static.append(command(['iverilog','-g2001','-s','upli_read_response_sender',f'-Pupli_read_response_sender.C_NUM_PORTS={p}','-o',str(case/'rtl.vvp'),*map(str,dependencies)],case,'g2001.log'))
  static.append(command(['verilator','--lint-only','-Wall','--top-module','upli_read_response_sender',f'-GC_NUM_PORTS={p}',*map(str,dependencies)],case,'lint.log'))
  script='read_verilog '+' '.join(map(str,dependencies))+f'\nhierarchy -check -top upli_read_response_sender -chparam C_NUM_PORTS {p}\nproc\nopt\nmemory_map\nopt\ncheck -assert\nstat\n';(case/'synthesis.ys').write_text(script)
  static.append(command(['yosys','-Q','-T','-s',str(case/'synthesis.ys')],case,'yosys.log'))
 summary=dict(label=args.label,sources=sources,cases=results,static=static,passed=all(r['passed'] for r in results) and all(r['exit']==0 for r in static),scope='staged native Read Response TX only; no RX/Tag collector/station/RAS proof')
 (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');manifest={str(p.relative_to(out)):sha(p.read_bytes()) for p in sorted(out.rglob('*')) if p.is_file()};(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(out,summary['passed']);return 0 if summary['passed'] else 1
if __name__=='__main__':sys.exit(main())

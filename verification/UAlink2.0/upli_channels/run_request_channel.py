#!/usr/bin/env python3
"""Request typed TX leaf regression.
Run: python3 verification/upli_channels/run_request_channel.py --label NEW --faults --static
Outputs: build/verification/upli_channels/request_channel/NEW with exact sources, independent vectors, logs and SHA256 hashes.
Next: integrate with the one shared native burst sender; do not add another bank.
"""
import argparse,hashlib,json,random,re,subprocess
from pathlib import Path
from request_reference import FIELDS,encode,observe
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--faults',action='store_true');p.add_argument('--static',action='store_true');a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
 stage=ROOT/'build/verification/upli_channels/request_channel'/a.label;stage.mkdir(parents=True,exist_ok=False)
 for name in ('run_request_channel.py','request_reference.py','request_channel_tb.sv'):(stage/name).write_bytes((HERE/name).read_bytes())
 for name in ('upli_request_channel.v','upli_parity.v'):(stage/name).write_bytes((ROOT/'rtl/upli'/name).read_bytes())
 rows=[]
 def add(r,v,d):rows.append((r,v,encode(d),*observe(r,v,d)))
 # These literals bypass the expected function as a guard against a shared pack bug.
 rows.append((1,1,(1<<189)-1,1,(1<<189)-1,1,0,1,0));rows.append((0,1,(1<<189)-1,0,0,0,0,0,0));rows.append((1,0,(1<<189)-1,0,0,0,0,0,0))
 for name,width in FIELDS:
  for bit in range(width):
   d={n:0 for n,w in FIELDS};d[name]=1<<bit
   for r,v in ((1,1),(1,0),(0,1)):add(r,v,d)
 rng=random.Random(941)
 for _ in range(400):add(rng.randrange(2),rng.randrange(2),{n:rng.getrandbits(w) for n,w in FIELDS})
 (stage/'vectors.txt').write_text(''.join(' '.join(format(x,'x') for x in row)+'\n' for row in rows))
 faults={
 'tag_high':('i_tag & {11{o_valid}}','(i_tag & 11\'h3ff) & {11{o_valid}}'),
 'auth_high':('i_auth_tag & {64{o_valid}}',"(i_auth_tag & 64'h7fffffffffffffff) & {64{o_valid}}"),
 'address_high':('i_address & {57{o_valid}}',"(i_address & 57'hffffffffffffff) & {57{o_valid}}"),
 'pool_field':('i_pool & {1{o_valid}}',"1'b0 & {1{o_valid}}"),
 'port_field':('i_port & {2{o_valid}}',"(i_port ^ 2'b01) & {2{o_valid}}"),
 'valid_bypass':('assign o_valid = i_rstn && i_valid;',"assign o_valid = i_rstn;"),
 }
 cases=[]
 for fault in [None,*list(faults if a.faults else {})]:
  folder=stage/(fault or 'normal');folder.mkdir();s=(stage/'upli_request_channel.v').read_text()
  if fault:
   old,new=faults[fault]
   if s.count(old)!=1:raise ValueError(fault+' anchor absent/ambiguous')
   s=s.replace(old,new)
  (folder/'upli_request_channel.v').write_text(s);(folder/'vectors.txt').write_bytes((stage/'vectors.txt').read_bytes());item={'fault':fault}
  for phase,cmd in [('compile',['iverilog','-g2012','-s','tb','-o','sim.vvp','upli_request_channel.v','../upli_parity.v','../request_channel_tb.sv']),('run',['vvp','sim.vvp'])]:
   with (folder/(phase+'.log')).open('w') as log:code=subprocess.run(cmd,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=45).returncode
   item[phase]={'command':cmd,'exit':code}
   if phase=='compile' and code:break
  log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
  item['passed']=item['compile']['exit']==0 and item.get('run',{}).get('exit')==(1 if fault else 0) and ('REQUEST_MISMATCH' if fault else 'REQUEST_PASS') in log;cases.append(item);print(fault or 'normal',item['passed'],log.strip(),flush=True)
 static=[]
 if a.static:
  (stage/'check.ys').write_text('read_verilog upli_request_channel.v upli_parity.v\nhierarchy -check -top upli_request_channel\nproc\nopt\ncheck -assert\nstat\n')
  for name,cmd in [('g2001',['iverilog','-g2001','-s','upli_request_channel','-o','compile.vvp','upli_request_channel.v','upli_parity.v']),('lint',['verilator','--lint-only','-Wall','--top-module','upli_request_channel','upli_request_channel.v','upli_parity.v']),('yosys',['yosys','-Q','-T','-s','check.ys'])]:
   with (stage/(name+'.log')).open('w') as log:code=subprocess.run(cmd,cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=45).returncode
   static.append({'tool':name,'exit':code,'command':cmd})
 result={'passed':all(c['passed'] for c in cases) and all(s['exit']==0 for s in static),'normal_vectors':len(rows),'cases':cases,'static':static,'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}}
 (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

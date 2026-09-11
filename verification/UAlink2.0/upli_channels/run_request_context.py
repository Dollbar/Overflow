#!/usr/bin/env python3
"""Run: python3 verification/upli_channels/run_request_context.py --label NEW [--ports 1|2|4] [--capacity 4] [--static].
Output: build/verification/upli_channels/request_context/NEW immutable vectors, source, logs and SHA manifest.
Next: review one-context-table ownership, then separately connect the real executor.
"""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
from request_context_reference import vectors,bridge_vectors
HERE=Path(__file__).resolve().parent
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
TOP='upli_endpoint_request_context'
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--ports',type=int,choices=(1,2,4));p.add_argument('--capacity',type=int,choices=range(1,17),default=4);p.add_argument('--integration',action='store_true');p.add_argument('--static',action='store_true');p.add_argument('--fault',choices=('tag','issue_release','token','station','order'))
 a=p.parse_args();a.red=False
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe label required')
 out=ROOT/'build/verification/upli_channels/request_context'/a.label;out.mkdir(parents=True,exist_ok=False);src=out/'source';src.mkdir();hashes={}
 paths=[ROOT/'rtl/upli'/(TOP+'.v'),HERE/'request_context_tb.sv',HERE/'request_context_reference.py',Path(__file__)]
 if a.integration:
  if a.capacity!=4:p.error('bridge integration uses capacity4')
  paths += [HERE/'request_context_bridge_tb.sv',ROOT/'rtl/upli/upli_endpoint_request_bridge.v']
 for f in paths:
  b=f.read_bytes();hashes[str(f)]=hashlib.sha256(b).hexdigest();target=src/(TOP+'.v' if f.name=='red_stub.v' else f.name)
  if a.fault and f.stem==TOP:
   t=b.decode();changes={
    'tag':('assign o_issue_payload = issue_payload;',"assign o_issue_payload = issue_payload ^ (o_issue_valid ? (184'd1 << 97) : 184'd0);"),
    'issue_release':('if(issue_fire)r_issued[issue_slot]<=1\'b1;',"if(issue_fire)begin r_issued[issue_slot]<=1'b1;r_active[issue_slot]<=1'b0;end"),
    'token':('&& (r_generation[release_slot]==release_generation)', ''),
    'station':('(r_station[scan]==i_request_station) && ', ''),
    'order':('assign issue_slot=pending_slots[read_ptr];','assign issue_slot=pending_slots[write_ptr];')}
   old,new=changes[a.fault]
   if old not in t:raise ValueError('fault anchor absent')
   b=t.replace(old,new,1).encode()
  target.write_bytes(b)
 def run(folder,name,cmd):
  with (folder/(name+'.log')).open('w') as f:
   try:code=subprocess.run([str(x) for x in cmd],cwd=folder,stdout=f,stderr=subprocess.STDOUT,timeout=120).returncode
   except subprocess.TimeoutExpired:code=124
  return {'command':[str(x) for x in cmd],'exit':code}
 cases=[]
 for ports in ([a.ports] if a.ports else [1,2,4]):
  folder=out/f'p{ports}';folder.mkdir();ref=vectors(folder/'vectors.txt',a.capacity,ports);commands={}
  commands['compile']=run(folder,'compile',['iverilog','-g2012','-s','tb',f'-Ptb.PORTS={ports}',f'-Ptb.CAP={a.capacity}','-o','sim.vvp',src/(TOP+'.v'),src/'request_context_tb.sv'])
  if commands['compile']['exit']==0:commands['run']=run(folder,'run',['vvp','sim.vvp','+VECTORS=vectors.txt'])
  log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
  passed=commands['compile']['exit']==0 and commands.get('run',{}).get('exit')==(1 if a.red or a.fault else 0) and ('CONTEXT_MISMATCH' if a.red or a.fault else 'CONTEXT_PASS') in log
  if a.static and not a.red and not a.fault and passed:
   for n,c in {
    'g2001':['iverilog','-g2001','-s',TOP,f'-P{TOP}.C_NUM_PORTS={ports}',f'-P{TOP}.CAPACITY={a.capacity}','-o','rtl.vvp',src/(TOP+'.v')],
    'lint':['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',TOP,f'-GC_NUM_PORTS={ports}',f'-GCAPACITY={a.capacity}',src/(TOP+'.v')],
    'yosys':['yosys','-Q','-T','-p',f'read_verilog {src/(TOP+".v")}; chparam -set C_NUM_PORTS {ports} -set CAPACITY {a.capacity} {TOP}; hierarchy -check -top {TOP}; proc; opt; check -assert; stat; write_json hierarchy.json']}.items():commands[n]=run(folder,n,c)
   passed=passed and all(v['exit']==0 for v in commands.values())
  cases.append({'ports':ports,'capacity':a.capacity,'reference':ref,'commands':commands,'passed':passed});print(ports,passed,log[-650:],flush=True)
  if a.integration:
   folder=out/f'p{ports}_bridge';folder.mkdir();ref=bridge_vectors(folder/'vectors.txt');commands={}
   commands['compile']=run(folder,'compile',['iverilog','-g2012','-s','bridge_tb',f'-Pbridge_tb.PORTS={ports}','-o','sim.vvp',src/(TOP+'.v'),src/'upli_endpoint_request_bridge.v',src/'request_context_bridge_tb.sv'])
   if commands['compile']['exit']==0:commands['run']=run(folder,'run',['vvp','sim.vvp','+VECTORS=vectors.txt'])
   log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
   passed=commands['compile']['exit']==0 and commands.get('run',{}).get('exit')==(1 if a.fault else 0) and ('CONTEXT_BRIDGE_MISMATCH' if a.fault else 'CONTEXT_BRIDGE_PASS') in log
   cases.append({'ports':ports,'kind':'bridge','reference':ref,'commands':commands,'passed':passed});print('bridge',ports,passed,log[-1000:],flush=True)
 result={'passed':all(c['passed'] for c in cases),'cases':cases,'sources_sha256':hashes,'artifacts_sha256':{str(f.relative_to(out)):hashlib.sha256(f.read_bytes()).hexdigest() for f in out.rglob('*') if f.is_file()}}
 (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

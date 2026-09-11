#!/usr/bin/env python3
"""Run actual Request/OrigData ordered SRAM-to-descriptor bridge.
Run: python3 verification/upli_channels/run_endpoint_request_bridge.py --label NEW --kd28-root PATH [--ports 1 2 4] [--fault tag_high|data_lane|reset_leak|retire_bypass] [--static].
Outputs: fresh build/verification/upli_channels/endpoint_request_bridge/NEW snapshots, dependency hashes, commands/logs/results.
Next: integrate checked native RX/role Drop and complete typed Endpoint/TL context; no full backend claim here.
"""
import argparse,hashlib,importlib.util,json,re,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
MODULE='upli_endpoint_request_bridge'
DEPS=('upli_ordered_receive_channel','upli_receive_channel','upli_receive_storage','upli_receive_fifo','upli_credit_return_queue','upli_credit_initializer','upli_credit_bank','upli_connection_side')

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--ports',type=int,nargs='+',choices=(1,2,4),default=[1,2,4]);p.add_argument('--fault',choices=('tag_high','data_lane','reset_leak','retire_bypass'));p.add_argument('--static',action='store_true');a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
 out=ROOT/'build/verification/upli_channels/endpoint_request_bridge'/a.label;out.mkdir(parents=True,exist_ok=False);(out/'sources').mkdir()
 hashes={};sources=[]
 for name in DEPS:
  f=ROOT/'rtl/upli'/f'{name}.v';b=f.read_bytes();target=out/'sources'/f.name;target.write_bytes(b);sources.append(str(target));hashes[str(f.relative_to(ROOT))]=hashlib.sha256(b).hexdigest()
 dep=json.loads((ROOT/'third_party/kd28_dependency.json').read_text());external={}
 for name,sha in dep['functional_sources_sha256'].items():
  f=a.kd28_root.resolve()/name;b=f.read_bytes()
  if hashlib.sha256(b).hexdigest()!=sha:raise ValueError('KD28 hash mismatch '+name)
  sources.append(str(f));external[name]=sha
 f=ROOT/'rtl/upli'/f'{MODULE}.v';b=f.read_bytes();original=hashlib.sha256(b).hexdigest()
 if a.fault and a.fault not in ('reset_leak','retire_bypass'):
  old,new={'tag_high':('assign o_request_payload = r_request;',"assign o_request_payload = r_request ^ (184'd1 << 97);"),'data_lane':('assign o_request_data = r_data;',"assign o_request_data = r_data ^ (r_request[27]?2048'd1:2048'd0);"),'reset_leak':("r_complete <= 1'b0; // reset_complete","r_complete <= r_complete; // reset_complete")}[a.fault]
  t=b.decode()
  if t.count(old)!=1:raise ValueError('fault anchor not unique')
  b=t.replace(old,new).encode()
 target=out/'sources'/f'{MODULE}.v';target.write_bytes(b);sources.append(str(target));hashes[f'rtl/upli/{MODULE}.v']=original
 for name,source_name in [('tb.sv','endpoint_request_bridge_tb.sv'),('reference.py','endpoint_request_bridge_reference.py')]:
  b=(HERE/source_name).read_bytes()
  if name=='tb.sv' and a.fault=='reset_leak':
   old='.i_rstn(rstn),.i_select_port(selected_port)';new='.i_rstn(rstn|reset_fault_enable),.i_select_port(selected_port)'
   if b.decode().count(old)!=1:raise ValueError('reset wiring fault anchor not unique')
   b=b.decode().replace(old,new).encode()
  if name=='tb.sv' and a.fault=='retire_bypass':
   old='.i_consumer_ready(consume_ready[g])';new='.i_consumer_ready(consume_ready[g]||request_ready)'
   if b.decode().count(old)!=1:raise ValueError('retire wiring fault anchor not unique')
   b=b.decode().replace(old,new).encode()
  (out/name).write_bytes(b)
 (out/'runner.py').write_bytes(Path(__file__).read_bytes())
 spec=importlib.util.spec_from_file_location('endpoint_request_bridge_reference',out/'reference.py');ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref);n=ref.write(out)
 cases=[]
 def execute(folder,name,cmd):
  with (folder/f'{name}.log').open('w') as log:
   try:code=subprocess.run(cmd,cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=180).returncode
   except subprocess.TimeoutExpired:code=124
  return {'command':cmd,'exit':code}
 for ports in a.ports:
  folder=out/f'p{ports}';folder.mkdir();binary=folder/'sim.vvp'
  compile=execute(folder,'compile',['iverilog','-g2012','-s','tb',f'-Ptb.PORTS={ports}',f'-Ptb.CASES={n}','-o',str(binary),*sources,str(out/'tb.sv')])
  run=execute(folder,'run',['vvp',str(binary)]) if compile['exit']==0 else {'exit':None};log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
  negative=bool(a.fault);passed=compile['exit']==0 and run['exit']==(1 if negative else 0) and ('BRIDGE_MISMATCH' if negative else 'BRIDGE_PASS') in log
  cases.append({'ports':ports,'compile':compile,'run':run,'passed':passed});print(ports,passed,log[-450:],flush=True)
 if a.static and not a.fault:
  for ports in a.ports:
   folder=out/f'p{ports}'
   for name,cmd in [('g2001',['iverilog','-g2001','-s',MODULE,f'-P{MODULE}.C_NUM_PORTS={ports}','-o',str(folder/'rtl.vvp'),str(target)]),('lint',['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',MODULE,f'-GC_NUM_PORTS={ports}',str(target)]),('yosys',['yosys','-Q','-T','-p',f'read_verilog {target}; chparam -set C_NUM_PORTS {ports} {MODULE}; hierarchy -check -top {MODULE}; proc; opt; check -assert; stat; write_json {folder}/rtl.json'])]:
    result=execute(folder,name,cmd);cases.append({'ports':ports,'static':name,**result,'passed':result['exit']==0})
 result={'passed':all(c['passed'] for c in cases),'fault':a.fault,'cases':cases,'source_sha256':hashes,'external_sha256':external,'artifacts_sha256':{str(f.relative_to(out)):hashlib.sha256(f.read_bytes()).hexdigest() for f in out.rglob('*') if f.is_file()}}
 (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

#!/usr/bin/env python3
"""Run --label NEW [--rtl PATH] [--faults]; retain logs/hash snapshots under ROOT/build/verification/upli_channels/response_collector/NEW. Next integrate only with the existing unique native RX credit owner."""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path
from response_collector_reference import generate
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve());HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--rtl',type=Path,default=ROOT/'rtl/upli/upli_endpoint_response_collector.v');p.add_argument('--faults',action='store_true');p.add_argument('--receive',action='store_true');p.add_argument('--kd28-root',type=Path);p.add_argument('--project-root',type=Path,default=ROOT);a=p.parse_args()
 if a.receive and not a.kd28_root:p.error('--receive requires --kd28-root')
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe fresh label')
 stage=ROOT/'build/verification/upli_channels/response_collector'/a.label;stage.mkdir(parents=True,exist_ok=False);source=stage/'source';source.mkdir();hashes={}
 for f in [a.rtl.resolve(),Path(__file__),HERE/'response_collector_tb.sv',HERE/'response_collector_reference.py',HERE/'response_collector_receive_tb.sv']:
  if f.exists():b=f.read_bytes();(source/f.name).write_bytes(b);hashes[str(f)]=hashlib.sha256(b).hexdigest()
 rtl=source/'upli_endpoint_response_collector.v';results=[]
 def run(folder,name,cmd):
  begin=time.monotonic()
  with (folder/(name+'.log')).open('w') as log:
   try:rc=subprocess.run([str(c) for c in cmd],cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=60).returncode
   except subprocess.TimeoutExpired:rc=124
  return {'command':[str(c) for c in cmd],'returncode':rc,'seconds':round(time.monotonic()-begin,3)}
 for ports in [1,2,4]:
  for fault in [None]+(['hold','pool','payload','retire','stop'] if ports==4 and a.faults else []):
   folder=stage/f'p{ports}{"_"+fault if fault else ""}';folder.mkdir();ref=generate(folder/'vectors.txt',ports);target=rtl;cmd={}
   if fault:
    old,new={'hold':('reg_locked[c] ? reg_port[c*2 +: 2] : i_select_port[c*2 +: 2]','i_select_port[c*2 +: 2]'), 'pool':('i_head_pool[c] & o_response_valid[c]',"1'b0 & o_response_valid[c]"),'payload':('i_read_payload & {619{o_response_valid[0]}}','{1\'b0,i_read_payload[617:0]} & {619{o_response_valid[0]}}'),'retire':('o_response_valid & i_retire_ready','o_response_valid'),'stop':('!i_stop && !o_fault_stop_request','!o_fault_stop_request')}[fault]
    text=rtl.read_text()
    if old not in text:raise ValueError('anchor '+fault)
    target=folder/rtl.name;target.write_text(text.replace(old,new,1))
   cmd['compile']=run(folder,'compile',['iverilog','-g2012','-s','response_collector_tb',f'-Presponse_collector_tb.PORTS={ports}','-o','sim.vvp',source/'response_collector_tb.sv',*([target] if target.exists() else [])])
   if cmd['compile']['returncode']==0:
    cmd['simulate']=run(folder,'simulate',['vvp','sim.vvp','+VECTORS=vectors.txt',f'+ROWS={ref["rows"]}'])
    if not fault:
     top='upli_endpoint_response_collector'
     for name,args in {'g2001':['iverilog','-g2001','-s',top,f'-P{top}.C_NUM_PORTS={ports}','-o','elab.vvp',target],'lint':['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',top,f'-GC_NUM_PORTS={ports}',target],'yosys':['yosys','-Q','-T','-p',f'read_verilog {target}; chparam -set C_NUM_PORTS {ports} {top}; hierarchy -check -top {top}; proc; opt; memory_map; check -assert; stat; write_json netlist.json']}.items():cmd[name]=run(folder,name,args)
   log=(folder/'simulate.log').read_text() if (folder/'simulate.log').exists() else ''
   passed=all(c['returncode']==0 for c in cmd.values()) and 'COLLECTOR_PASS' in log
   if fault:passed=cmd['compile']['returncode']==0 and cmd.get('simulate',{}).get('returncode')==1 and 'COLLECTOR_CHECK' in log
   results.append({'ports':ports,'fault':fault,'reference':ref,'commands':cmd,'passed':passed});print(ports,fault,passed,flush=True)
 if rtl.exists():
  folder=stage/'invalid_ports3';folder.mkdir();cmd=run(folder,'compile',['iverilog','-g2001','-s','upli_endpoint_response_collector','-Pupli_endpoint_response_collector.C_NUM_PORTS=3','-o','bad.vvp',rtl])
  results.append({'invalid_ports':3,'commands':{'compile':cmd},'passed':cmd['returncode']!=0 and 'upli_endpoint_response_collector_ports_invalid' in (folder/'compile.log').read_text()})
 if a.receive:
  project=a.project_root.resolve();kd=a.kd28_root.resolve();deps=json.loads((project/'third_party/kd28_dependency.json').read_text())['functional_sources_sha256'];external_paths={(kd/name).resolve():name for name in deps};rx_source=stage/'receive_source';rx_source.mkdir();rx_files=[]
  for f in [f for f in (project/'rtl').rglob('*.v') if f.name!=rtl.name]+[kd/n for n in deps]:
   blob=f.read_bytes();digest=hashlib.sha256(blob).hexdigest()
   resolved=f.resolve()
   if resolved in external_paths and digest!=deps[external_paths[resolved]]:raise ValueError('KD28 hash mismatch')
   target=rx_source/f.name
   if target.exists():raise ValueError('source basename collision')
   target.write_bytes(blob);hashes[str(f)]=digest;rx_files.append(target)
  for ports in [1,2,4]:
   for fault in [None]+(['pool','retire','hold','payload','credit_vc'] if a.faults and ports==4 else []):
    folder=stage/f'receive_p{ports}{"_"+fault if fault else ""}';folder.mkdir();target=rtl;cmd={};case_rx_files=rx_files
    if fault=='credit_vc':
     old_file=next(f for f in rx_files if f.name=='upli_credit_return_queue.v');new_file=folder/old_file.name;text=old_file.read_text();anchor='reg_vc_o <= head_vc'
     if anchor not in text:raise ValueError('credit VC anchor')
     new_file.write_text(text.replace(anchor,"reg_vc_o <= 2'd0",1));case_rx_files=[new_file if f==old_file else f for f in rx_files]
    elif fault:
     old,new={'hold':('reg_locked[c] ? reg_port[c*2 +: 2] : i_select_port[c*2 +: 2]','i_select_port[c*2 +: 2]'),'pool':('i_head_pool[c] & o_response_valid[c]',"1'b0 & o_response_valid[c]"),'retire':('o_response_valid & i_retire_ready','o_response_valid'),'payload':('i_read_payload & {619{o_response_valid[0]}}',"{1'b0,i_read_payload[617:0]} & {619{o_response_valid[0]}}")} [fault]
     target=folder/rtl.name;target.write_text(rtl.read_text().replace(old,new,1))
    cmd['compile']=run(folder,'compile',['iverilog','-g2012','-s','response_collector_receive_tb',f'-Presponse_collector_receive_tb.PORTS={ports}','-o','sim.vvp',source/'response_collector_receive_tb.sv',target,*case_rx_files])
    if cmd['compile']['returncode']==0:cmd['simulate']=run(folder,'simulate',['vvp','sim.vvp'])
    log=(folder/'simulate.log').read_text() if (folder/'simulate.log').exists() else ''
    passed=all(c['returncode']==0 for c in cmd.values()) and 'COLLECTOR_RX_PASS' in log
    if fault:passed=cmd['compile']['returncode']==0 and cmd.get('simulate',{}).get('returncode')==1 and 'COLLECTOR_RX_' in log
    results.append({'receive':True,'ports':ports,'fault':fault,'commands':cmd,'passed':passed});print('receive',ports,fault,passed,log[-180:],flush=True)
 result={'passed':all(c['passed'] for c in results),'cases':results,'sources_sha256':hashes,'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}};(stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

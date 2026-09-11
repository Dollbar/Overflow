#!/usr/bin/env python3
"""Run: python3 verification/upli_channels/run_role_fault.py --label NEW [--rtl PATH] [--faults].
Outputs ROOT/build/verification/upli_channels/role_fault/NEW source/vector/log/hash evidence.
Next integrate this local diagnostic scope owner; acknowledgement never restores traffic.
"""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path
from role_fault_reference import generate
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve());HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--rtl',type=Path,default=ROOT/'rtl/upli/upli_rx_role_fault_controller.v');p.add_argument('--faults',action='store_true');p.add_argument('--ports',type=int,choices=(1,2,4));p.add_argument('--receive',action='store_true');p.add_argument('--kd28-root',type=Path);p.add_argument('--project-root',type=Path,default=ROOT);a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('fresh safe label')
 if a.receive and not a.kd28_root:p.error('--receive needs explicit --kd28-root')
 stage=ROOT/'build/verification/upli_channels/role_fault'/a.label;stage.mkdir(parents=True,exist_ok=False);source=stage/'source';source.mkdir();hashes={}
 for f in [a.rtl.resolve(),HERE/'role_fault_tb.sv',HERE/'role_fault_reference.py',HERE/'role_fault_receive_tb.sv',Path(__file__)]:
  if f.exists():blob=f.read_bytes();(source/f.name).write_bytes(blob);hashes[str(f)]=hashlib.sha256(blob).hexdigest()
 rtl=source/'upli_rx_role_fault_controller.v';results=[]
 def run(folder,name,cmd):
  begin=time.monotonic()
  with (folder/(name+'.log')).open('w') as log:
   try:rc=subprocess.run([str(c) for c in cmd],cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=60).returncode
   except subprocess.TimeoutExpired:rc=124
  return {'command':[str(c) for c in cmd],'returncode':rc,'seconds':round(time.monotonic()-begin,3)}
 for ports in ([a.ports] if a.ports else [1,2,4]):
  for roles,tl in [(1,0),(2,0),(2,1)]:
   faults=[None]+(['late_drop','ack_clear','data_fatal','role_scope','credit_ignored','credit_direction'] if a.faults and ports==4 and roles==2 and tl==0 else [])
   for fault in faults:
    folder=stage/f'p{ports}_r{roles}_tl{tl}{"_"+fault if fault else ""}';folder.mkdir();ref=generate(folder/'vectors.txt',ports,roles,tl);target=rtl
    if fault:
     old,new={
      'late_drop':('reg_drop | role_fatal','reg_drop'),
      'ack_clear':('reg_drop | role_fatal', '(reg_drop | role_fatal) & ~i_fault_ack'),
      'data_fatal':('i_control_error | i_auth_error','i_control_error | i_data_error | i_auth_error'),
      'role_scope':("4'b0110", "4'b1111"),
      'credit_ignored':('i_credit_control_error & C_CREDIT_MASK',"4'd0 & C_CREDIT_MASK"),
      'credit_direction':('i_credit_control_error & C_CREDIT_MASK','i_credit_control_error & C_CHANNEL_MASK')}[fault]
     text=rtl.read_text()
     if old not in text:raise ValueError('fault anchor absent '+fault)
     target=folder/'upli_rx_role_fault_controller.v';target.write_text(text.replace(old,new,1))
    cmd={};cmd['compile']=run(folder,'compile',['iverilog','-g2012','-s','role_fault_tb',f'-Prole_fault_tb.PORTS={ports}',f'-Prole_fault_tb.ROLES={roles}',f'-Prole_fault_tb.IS_TL={tl}','-o','sim.vvp',source/'role_fault_tb.sv',*([target] if target.exists() else [])])
    if cmd['compile']['returncode']==0:
     cmd['simulate']=run(folder,'simulate',['vvp','sim.vvp','+VECTORS=vectors.txt',f'+ROWS={ref["rows"]}'])
     if not fault:
      top='upli_rx_role_fault_controller'
      for name,args in {'g2001':['iverilog','-g2001','-s',top,f'-P{top}.C_NUM_PORTS={ports}',f'-P{top}.C_NUM_ROLES={roles}',f'-P{top}.C_IS_TL={tl}','-o','elab.vvp',target],
       'lint':['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',top,f'-GC_NUM_PORTS={ports}',f'-GC_NUM_ROLES={roles}',f'-GC_IS_TL={tl}',target],
       'yosys':['yosys','-Q','-T','-p',f'read_verilog {target}; chparam -set C_NUM_PORTS {ports} -set C_NUM_ROLES {roles} -set C_IS_TL {tl} {top}; hierarchy -check -top {top}; proc; opt; check -assert; stat; write_json netlist.json']}.items():cmd[name]=run(folder,name,args)
    log=(folder/'simulate.log').read_text() if (folder/'simulate.log').exists() else ''
    passed=all(c['returncode']==0 for c in cmd.values()) and 'ROLE_PASS' in log
    if fault:passed=cmd['compile']['returncode']==0 and cmd.get('simulate',{}).get('returncode')==1 and ('ROLE_PRE' in log or 'ROLE_POST' in log)
    results.append({'ports':ports,'roles':roles,'is_tl':tl,'fault':fault,'reference':ref,'commands':cmd,'passed':passed});print(ports,roles,tl,fault,passed,flush=True)
 if rtl.exists():
  for name,ports,roles,tl in [('ports3',3,2,0),('roles3',1,3,0),('tl2',1,2,2),('tl_single_role',1,1,1)]:
   folder=stage/('invalid_'+name);folder.mkdir();cmd=run(folder,'compile',['iverilog','-g2001','-s','upli_rx_role_fault_controller',f'-Pupli_rx_role_fault_controller.C_NUM_PORTS={ports}',f'-Pupli_rx_role_fault_controller.C_NUM_ROLES={roles}',f'-Pupli_rx_role_fault_controller.C_IS_TL={tl}','-o','invalid.vvp',rtl])
   log=(folder/'compile.log').read_text();passed=cmd['returncode']!=0 and 'upli_rx_role_fault_controller_parameters_invalid' in log
   results.append({'invalid':name,'commands':{'compile':cmd},'passed':passed})
 if a.receive:
  project=a.project_root.resolve();deps=json.loads((project/'third_party/kd28_dependency.json').read_text())['functional_sources_sha256'];rx_source=stage/'receive_source';rx_source.mkdir();rx_files=[]
  paths=[f for f in (project/'rtl').rglob('*.v') if f.name!='upli_rx_role_fault_controller.v']+[a.kd28_root.resolve()/n for n in deps]
  for f in paths:
   blob=f.read_bytes()
   if f.is_relative_to(a.kd28_root.resolve()) and str(f.relative_to(a.kd28_root.resolve())) in deps and hashlib.sha256(blob).hexdigest()!=deps[str(f.relative_to(a.kd28_root.resolve()))]:raise ValueError('KD28 source mismatch')
   target=rx_source/f.name
   if target.exists():raise ValueError('source filename collision')
   target.write_bytes(blob);hashes[str(f)]=hashlib.sha256(blob).hexdigest();rx_files.append(target)
  for ports in ([a.ports] if a.ports else [1,2,4]):
   for roles,tl in [(1,0),(2,0),(2,1)]:
    folder=stage/f'receive_p{ports}_r{roles}_tl{tl}';folder.mkdir();cmd={}
    cmd['compile']=run(folder,'compile',['iverilog','-g2012','-s','role_fault_receive_tb',f'-Prole_fault_receive_tb.PORTS={ports}',f'-Prole_fault_receive_tb.ROLES={roles}',f'-Prole_fault_receive_tb.IS_TL={tl}','-o','sim.vvp',source/'role_fault_receive_tb.sv',rtl,*rx_files])
    if cmd['compile']['returncode']==0:cmd['simulate']=run(folder,'simulate',['vvp','sim.vvp'])
    log=(folder/'simulate.log').read_text() if (folder/'simulate.log').exists() else ''
    passed=all(c['returncode']==0 for c in cmd.values()) and 'ROLE_RX_PASS' in log
    results.append({'receive':True,'ports':ports,'roles':roles,'is_tl':tl,'commands':cmd,'passed':passed});print('receive',ports,roles,tl,passed,log[-130:],flush=True)
  if a.faults:
   for fault in ['late_drop','data_fatal','credit_direction']:
    folder=stage/('receive_fault_'+fault);folder.mkdir();target=folder/'upli_rx_role_fault_controller.v'
    old,new={'late_drop':('reg_drop | role_fatal','reg_drop'),'data_fatal':('i_control_error | i_auth_error','i_control_error | i_data_error | i_auth_error'),'credit_direction':('i_credit_control_error & C_CREDIT_MASK','i_credit_control_error & C_CHANNEL_MASK')}[fault]
    text=rtl.read_text()
    if old not in text:raise ValueError('receive fault anchor')
    target.write_text(text.replace(old,new,1));cmd={}
    cmd['compile']=run(folder,'compile',['iverilog','-g2012','-s','role_fault_receive_tb','-Prole_fault_receive_tb.PORTS=4','-Prole_fault_receive_tb.ROLES=2','-Prole_fault_receive_tb.IS_TL=0','-o','sim.vvp',source/'role_fault_receive_tb.sv',target,*rx_files])
    if cmd['compile']['returncode']==0:cmd['simulate']=run(folder,'simulate',['vvp','sim.vvp'])
    log=(folder/'simulate.log').read_text() if (folder/'simulate.log').exists() else ''
    passed=cmd['compile']['returncode']==0 and cmd.get('simulate',{}).get('returncode')==1 and 'ROLE_RX_' in log
    results.append({'receive':True,'fault':fault,'ports':4,'roles':2,'is_tl':0,'commands':cmd,'passed':passed});print('receive_fault',fault,passed,flush=True)
 result={'passed':all(c['passed'] for c in results),'cases':results,'sources_sha256':hashes,'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}};(stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

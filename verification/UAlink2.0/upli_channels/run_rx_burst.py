#!/usr/bin/env python3
"""Run --label NEW [--rtl PATH] [--faults]; retain logs/hash snapshots under ROOT/build/verification/upli_channels/rx_burst/NEW. Next route diagnostics into the existing role owner; this module never filters traffic."""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path
from rx_burst_reference import generate
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve());HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--rtl',type=Path,default=ROOT/'rtl/upli/upli_native_rx_burst_monitor.v');p.add_argument('--faults',action='store_true');p.add_argument('--receive',action='store_true');p.add_argument('--kd28-root',type=Path);p.add_argument('--project-root',type=Path,default=ROOT);a=p.parse_args()
 if a.receive and not a.kd28_root:p.error('--receive requires --kd28-root')
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe fresh label')
 stage=ROOT/'build/verification/upli_channels/rx_burst'/a.label;stage.mkdir(parents=True,exist_ok=False);source=stage/'source';source.mkdir();hashes={}
 for f in [a.rtl.resolve(),Path(__file__),HERE/'rx_burst_tb.sv',HERE/'rx_burst_reference.py',HERE/'rx_burst_path_bind.svh']:
  if f.exists():b=f.read_bytes();(source/f.name).write_bytes(b);hashes[str(f)]=hashlib.sha256(b).hexdigest()
 rtl=source/'upli_native_rx_burst_monitor.v';results=[]
 def run(folder,name,cmd):
  begin=time.monotonic()
  with (folder/(name+'.log')).open('w') as log:
   try:rc=subprocess.run([str(c) for c in cmd],cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=60).returncode
   except subprocess.TimeoutExpired:rc=124
  return {'command':[str(c) for c in cmd],'returncode':rc,'seconds':round(time.monotonic()-begin,3)}
 for ports in [1,2,4]:
  for fault in [None]+(['first','gap','offset','last','overlay'] if ports==4 and a.faults else []):
   folder=stage/f'p{ports}{"_"+fault if fault else ""}';folder.mkdir();ref=generate(folder/'vectors.txt',ports);target=rtl;cmd={}
   if fault:
    old,new={'first':('flag_start && !flag_data',"1'b0 && !flag_data"),'gap':('flag_due && !flag_data',"1'b0 && !flag_data"),'offset':('i_data_offset != expected_offset',"1'b0"),'last':('i_data_last != expected_last',"1'b0"),'overlay':('flag_start && (i_req_num_beats != 2\'d0)',"flag_request && (i_req_num_beats != 2'd0)")}[fault]
    text=rtl.read_text()
    if old not in text:raise ValueError('anchor '+fault)
    target=folder/rtl.name;target.write_text(text.replace(old,new,1))
   cmd['compile']=run(folder,'compile',['iverilog','-g2012','-s','rx_burst_tb',f'-Prx_burst_tb.PORTS={ports}','-o','sim.vvp',source/'rx_burst_tb.sv',*([target] if target.exists() else [])])
   if cmd['compile']['returncode']==0:
    cmd['simulate']=run(folder,'simulate',['vvp','sim.vvp','+VECTORS=vectors.txt',f'+ROWS={ref["rows"]}'])
    if not fault:
     top='upli_native_rx_burst_monitor'
     for name,args in {'g2001':['iverilog','-g2001','-s',top,f'-P{top}.C_NUM_PORTS={ports}','-o','elab.vvp',target],'lint':['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',top,f'-GC_NUM_PORTS={ports}',target],'yosys':['yosys','-Q','-T','-p',f'read_verilog {target}; chparam -set C_NUM_PORTS {ports} {top}; hierarchy -check -top {top}; proc; opt; memory_map; check -assert; stat; write_json netlist.json']}.items():cmd[name]=run(folder,name,args)
   log=(folder/'simulate.log').read_text() if (folder/'simulate.log').exists() else ''
   passed=all(c['returncode']==0 for c in cmd.values()) and 'RX_BURST_PASS' in log
   if fault:passed=cmd['compile']['returncode']==0 and cmd.get('simulate',{}).get('returncode')==1 and 'RX_BURST_CHECK' in log
   results.append({'ports':ports,'fault':fault,'reference':ref,'commands':cmd,'passed':passed});print(ports,fault,passed,flush=True)
 if rtl.exists():
  folder=stage/'invalid_ports3';folder.mkdir();cmd=run(folder,'compile',['iverilog','-g2001','-s','upli_native_rx_burst_monitor','-Pupli_native_rx_burst_monitor.C_NUM_PORTS=3','-o','bad.vvp',rtl])
  results.append({'invalid_ports':3,'commands':{'compile':cmd},'passed':cmd['returncode']!=0 and 'upli_native_rx_burst_monitor_ports_invalid' in (folder/'compile.log').read_text()})
 if a.receive:
  project=a.project_root.resolve();kd=a.kd28_root.resolve();deps=json.loads((project/'third_party/kd28_dependency.json').read_text())['functional_sources_sha256'];external_paths={(kd/name).resolve():name for name in deps};rx_source=stage/'receive_source';rx_source.mkdir();rx_files=[]
  for f in [f for f in (project/'rtl/upli').glob('*.v') if f.name!=rtl.name]+[kd/n for n in deps]:
   blob=f.read_bytes();digest=hashlib.sha256(blob).hexdigest()
   resolved=f.resolve()
   if resolved in external_paths and digest!=deps[external_paths[resolved]]:raise ValueError('KD28 source mismatch')
   target=rx_source/f.name
   if target.exists():raise ValueError('source basename collision')
   target.write_bytes(blob);hashes[str(f)]=digest;rx_files.append(target)
  original_tb=project/'verification/ip_tops/endpoint_native_rx_path_tb.sv';blob=original_tb.read_bytes();hashes[str(original_tb)]=hashlib.sha256(blob).hexdigest();(source/original_tb.name).write_bytes(blob)
  for ports in [1,2,4]:
   for fault in [None]+(['first','gap','offset','last','vc'] if ports==4 and a.faults else []):
    folder=stage/f'path_p{ports}{"_"+fault if fault else ""}';folder.mkdir();bind=(source/'rx_burst_path_bind.svh').read_text()
    if fault:
     old,new={'first':('observed_data_valid=o_data_valid','observed_data_valid=o_data_valid && (o_data_offset!=0)'), 'gap':('observed_data_valid=o_data_valid','observed_data_valid=o_data_valid && (o_data_offset!=1)'), 'offset':('observed_data_offset=o_data_offset','observed_data_offset=o_data_offset ^ 2\'d1'), 'last':('observed_data_last=o_data_last','observed_data_last=~o_data_last'), 'vc':('observed_data_vc=o_data_vc','observed_data_vc=o_data_vc ^ 2\'d1')}[fault]
     if old not in bind:raise ValueError('path anchor '+fault)
     bind=bind.replace(old,new,1)
    text=blob.decode()
    if text.count('endmodule')!=1:raise ValueError('path TB insertion boundary')
    tb=folder/'tb.sv';tb.write_text(text.replace('endmodule',bind+'\nendmodule'))
    cmd={'compile':run(folder,'compile',['iverilog','-g2012','-s','tb',f'-Ptb.PORTS={ports}','-o','sim.vvp',tb,rtl,*rx_files])}
    if cmd['compile']['returncode']==0:cmd['simulate']=run(folder,'simulate',['vvp','sim.vvp'])
    log=(folder/'simulate.log').read_text() if (folder/'simulate.log').exists() else ''
    passed=all(c['returncode']==0 for c in cmd.values()) and 'PATH_PASS' in log and 'BURST_PATH_COUNTS' in log
    if fault:passed=cmd['compile']['returncode']==0 and cmd.get('simulate',{}).get('returncode')==1 and 'BURST_PATH_ERROR' in log
    results.append({'path':True,'ports':ports,'fault':fault,'commands':cmd,'passed':passed});print('path',ports,fault,passed,log[-250:],flush=True)
 result={'passed':all(c['passed'] for c in results),'cases':results,'sources_sha256':hashes,'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}};(stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

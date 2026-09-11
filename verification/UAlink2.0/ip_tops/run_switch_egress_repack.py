#!/usr/bin/env python3
"""Run --label NEW [--rtl PATH] [--faults]. Outputs ROOT/build/verification/ip_tops/switch_egress_repack/NEW. Next implement the confirmed TL decode/prepared association boundary; this is a typed local record handoff."""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path
from switch_egress_repack_reference import generate
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve());HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--rtl',type=Path,default=ROOT/'rtl/switch/switch_egress_repack.v');p.add_argument('--faults',action='store_true');a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('fresh safe label')
 stage=ROOT/'build/verification/ip_tops/switch_egress_repack'/a.label;stage.mkdir(parents=True,exist_ok=False);source=stage/'source';source.mkdir();hashes={}
 for f in [a.rtl.resolve(),Path(__file__),HERE/'switch_egress_repack_tb.sv',HERE/'switch_egress_repack_reference.py']:
  blob=f.read_bytes();(source/f.name).write_bytes(blob);hashes[str(f)]=hashlib.sha256(blob).hexdigest()
 rtl=source/'switch_egress_repack.v';results=[]
 def run(folder,name,cmd):
  begin=time.monotonic()
  with (folder/(name+'.log')).open('w') as log:
   try:rc=subprocess.run([str(c) for c in cmd],cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=60).returncode
   except subprocess.TimeoutExpired:rc=124
  return {'command':[str(c) for c in cmd],'returncode':rc,'seconds':round(time.monotonic()-begin,3)}
 for ports in [1,2,4]:
  for vcs in [1,2,4]:
   for fault in [None]+(['ready','header','aux','msg','flit','class','vc','last','token'] if a.faults and ports==4 and vcs==4 else []):
    folder=stage/f'p{ports}_v{vcs}{"_"+fault if fault else ""}';folder.mkdir();ref=generate(folder/'vectors.txt',ports,vcs);target=rtl
    if fault:
     old,new={'ready':('(!reg_valid||i_ready[p])',"1'b1"),'header':('reg_record[543:520]', 'reg_record[542:519]'),'aux':('reg_record[519:514]',"6'd0"),'msg':('reg_record[513:512]', 'reg_record[512:511]'),'flit':('reg_record[511:0]',"{1'b0,reg_record[510:0]}"),'class':('reg_response&&o_valid[p]',"1'b0&&o_valid[p]"),'vc':('reg_vc&{2{o_valid[p]}}',"2'd0&{2{o_valid[p]}}"),'last':('reg_last&&o_valid[p]',"1'b0&&o_valid[p]"),'token':('reg_token&{TOKEN_WIDTH{o_valid[p]}}',"{TOKEN_WIDTH{1'b0}}&{TOKEN_WIDTH{o_valid[p]}}")}[fault]
     text=rtl.read_text()
     if text.count(old)!=1:raise ValueError('fault anchor '+fault)
     target=folder/rtl.name;target.write_text(text.replace(old,new,1))
    top='switch_egress_repack';cmd={'compile':run(folder,'compile',['iverilog','-g2012','-s','switch_egress_repack_tb',f'-Pswitch_egress_repack_tb.P={ports}',f'-Pswitch_egress_repack_tb.V={vcs}','-o','sim.vvp',source/'switch_egress_repack_tb.sv',target])}
    if cmd['compile']['returncode']==0:
     cmd['simulate']=run(folder,'simulate',['vvp','sim.vvp','+VECTORS=vectors.txt',f'+ROWS={ref["rows"]}'])
     if not fault:
      for name,args in {'g2001':['iverilog','-g2001','-s',top,f'-P{top}.PORTS={ports}',f'-P{top}.VCS={vcs}','-o','elab.vvp',target],'lint':['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',top,f'-GPORTS={ports}',f'-GVCS={vcs}',target],'yosys':['yosys','-Q','-T','-p',f'read_verilog {target}; chparam -set PORTS {ports} -set VCS {vcs} {top}; hierarchy -check -top {top}; proc; opt; check -assert; stat; write_json netlist.json']}.items():cmd[name]=run(folder,name,args)
    log=(folder/'simulate.log').read_text() if (folder/'simulate.log').exists() else ''
    passed=all(c['returncode']==0 for c in cmd.values()) and 'REPACK_PASS' in log
    if fault:passed=cmd['compile']['returncode']==0 and cmd.get('simulate',{}).get('returncode')==1 and 'REPACK_CHECK' in log
    results.append({'ports':ports,'vcs':vcs,'fault':fault,'reference':ref,'commands':cmd,'passed':passed});print(ports,vcs,fault,passed,flush=True)
 for name,ports,vcs in [('ports3',3,1),('vcs3',1,3)]:
  folder=stage/('invalid_'+name);folder.mkdir();cmd=run(folder,'compile',['iverilog','-g2001','-s','switch_egress_repack',f'-Pswitch_egress_repack.PORTS={ports}',f'-Pswitch_egress_repack.VCS={vcs}','-o','bad.vvp',rtl]);results.append({'invalid':name,'commands':{'compile':cmd},'passed':cmd['returncode']!=0 and 'switch_egress_repack_parameters_invalid' in (folder/'compile.log').read_text()})
 result={'passed':all(c['passed'] for c in results),'cases':results,'sources_sha256':hashes,'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}};(stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

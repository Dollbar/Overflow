#!/usr/bin/env python3
"""Run --label NEW [--rtl PATH] [--faults]. Outputs ROOT/build/verification/ras/isolation/NEW. Next connect real transaction and dummy completion owners before enabling any recovery handshake."""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path
from isolation_reference import generate
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve());HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--rtl',type=Path,default=ROOT/'rtl/ras/ras_originator_isolation.v');p.add_argument('--faults',action='store_true');p.add_argument('--epoch-width',type=int,default=2,choices=range(2,17));p.add_argument('--case',nargs=3,type=int,metavar=('PORTS','CAPACITY','SWITCH'));a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('fresh safe label')
 stage=ROOT/'build/verification/ras/isolation'/a.label;stage.mkdir(parents=True,exist_ok=False);source=stage/'source';source.mkdir();hashes={}
 for f in [a.rtl.resolve(),Path(__file__),HERE/'isolation_tb.sv',HERE/'isolation_reference.py']:
  blob=f.read_bytes();(source/f.name).write_bytes(blob);hashes[str(f)]=hashlib.sha256(blob).hexdigest()
 rtl=source/'ras_originator_isolation.v';results=[]
 def run(folder,name,cmd):
  begin=time.monotonic()
  with (folder/(name+'.log')).open('w') as log:
   try:rc=subprocess.run([str(c) for c in cmd],cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=60).returncode
   except subprocess.TimeoutExpired:rc=124
  return {'command':[str(c) for c in cmd],'returncode':rc,'seconds':round(time.monotonic()-begin,3)}
 matrix=[tuple(a.case)] if a.case else [(p,c,s)for p in [1,2,4]for c in [1,2,3,4]for s in [0,1]]
 for ports,capacity,sw in matrix:
  for fault in [None]+(['early_free','late_complete','wrap','scope','stale_epoch','quiet','tag_high','unissued_done','hold'] if a.faults and (ports,capacity,sw)==(4,4,1) else []):
   folder=stage/f'p{ports}_c{capacity}_s{sw}{"_"+fault if fault else ""}';folder.mkdir();ref=generate(folder/'vectors.txt',ports,capacity,sw,a.epoch_width);target=rtl
   if fault:
    old,new={'early_free':("else if(dummy_request)reg_issued<=1'b1;","else if(dummy_request)begin reg_issued<=1'b1;reg_pending<=1'b0;end"),'late_complete':('&&!slot_isolated[s]&&!reg_issued',''),'wrap':('&&flag_epoch_available&&','&&'),'scope':('(IS_SWITCH==1)?','(IS_SWITCH==0)?'),'stale_epoch':('(i_dummy_done_epoch==reg_epoch)',"1'b1"),'quiet':('&&i_quiescent&&','&&'),'tag_high':('reg_tag<=i_track_tag',"reg_tag<={1'b0,i_track_tag[9:0]}"),'unissued_done':('reg_pending&&reg_issued&&slot_isolated[s]','reg_pending&&slot_isolated[s]'),'hold':('&&(!reg_hold||(index[1:0]==reg_hold_slot))','')}[fault]
    text=rtl.read_text()
    if text.count(old)!=1:raise ValueError('fault anchor '+fault)
    target=folder/rtl.name;target.write_text(text.replace(old,new,1))
   top='ras_originator_isolation';cmd={'compile':run(folder,'compile',['iverilog','-g2012','-s','isolation_tb',f'-Pisolation_tb.P={ports}',f'-Pisolation_tb.C={capacity}',f'-Pisolation_tb.SW={sw}',f'-Pisolation_tb.E={a.epoch_width}','-o','sim.vvp',source/'isolation_tb.sv',target])}
   if cmd['compile']['returncode']==0:
    cmd['simulate']=run(folder,'simulate',['vvp','sim.vvp','+VECTORS=vectors.txt',f'+ROWS={ref["rows"]}'])
    if not fault:
     for name,args in {'g2001':['iverilog','-g2001','-s',top,f'-P{top}.PORTS={ports}',f'-P{top}.CAPACITY={capacity}',f'-P{top}.IS_SWITCH={sw}',f'-P{top}.EPOCH_WIDTH={a.epoch_width}','-o','elab.vvp',target],'lint':['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',top,f'-GPORTS={ports}',f'-GCAPACITY={capacity}',f'-GIS_SWITCH={sw}',f'-GEPOCH_WIDTH={a.epoch_width}',target],'yosys':['yosys','-Q','-T','-p',f'read_verilog {target}; chparam -set PORTS {ports} -set CAPACITY {capacity} -set IS_SWITCH {sw} -set EPOCH_WIDTH {a.epoch_width} {top}; hierarchy -check -top {top}; proc; opt; memory_map; check -assert; stat; write_json netlist.json']}.items():cmd[name]=run(folder,name,args)
   log=(folder/'simulate.log').read_text()if(folder/'simulate.log').exists()else'';passed=all(c['returncode']==0 for c in cmd.values())and'ISOLATION_PASS'in log
   if fault:passed=cmd['compile']['returncode']==0 and cmd.get('simulate',{}).get('returncode')==1 and 'ISOLATION_CHECK'in log
   results.append({'ports':ports,'capacity':capacity,'is_switch':sw,'epoch_width':a.epoch_width,'fault':fault,'reference':ref,'commands':cmd,'passed':passed});print(ports,capacity,sw,fault,passed,log[-130:],flush=True)
 result={'passed':all(c['passed']for c in results),'cases':results,'sources_sha256':hashes,'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest()for f in stage.rglob('*')if f.is_file()}};(stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed']else 1
if __name__=='__main__':raise SystemExit(main())

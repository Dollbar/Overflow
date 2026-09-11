#!/usr/bin/env python3
"""Run --label NEW [--ledger FILE] [--faults]. Outputs ROOT/build/verification/ras/dummy/NEW. Next connect actual Tag/application owners before enabling isolation recovery."""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path
from dummy_reference import generate
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve());HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--ledger',type=Path,default=ROOT/'rtl/ras/ras_originator_isolation.v');p.add_argument('--faults',action='store_true');p.add_argument('--case',nargs=3,type=int);p.add_argument('--epoch-width',type=int,default=2,choices=range(2,17));a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('fresh safe label required')
 stage=ROOT/'build/verification/ras/dummy'/a.label;stage.mkdir(parents=True,exist_ok=False);source=stage/'source';source.mkdir();hashes={}
 sources=[ROOT/'rtl/ras/ras_dummy_completion.v',ROOT/'rtl/ras/ras_isolation_completion.v',a.ledger.resolve(),Path(__file__),HERE/'dummy_tb.sv',HERE/'dummy_reference.py']
 for f in sources:
  blob=f.read_bytes();(source/f.name).write_bytes(blob);hashes[str(f)]=hashlib.sha256(blob).hexdigest()
 def run(folder,name,cmd):
  start=time.monotonic()
  with(folder/(name+'.log')).open('w')as out:
   try:rc=subprocess.run([str(c)for c in cmd],stdout=out,stderr=subprocess.STDOUT,cwd=folder,timeout=60).returncode
   except subprocess.TimeoutExpired:rc=124
  return {'command':[str(c)for c in cmd],'returncode':rc,'seconds':round(time.monotonic()-start,3)}
 matrix=[(1,1,0,1)]+[(p,c,s,0)for p,c,s in ([a.case]if a.case else[(p,c,s)for p in [1,2,4]for c in [1,2,3,4]for s in [0,1]])];results=[]
 mutations={
 'early_done':('ras_dummy_completion.v','if(flag_last)reg_state<=C_DONE;','if(1\'b1)reg_state<=C_DONE;'),
 'no_ready':('ras_dummy_completion.v','o_response_valid&&i_response_ready','o_response_valid'),
 'tag_high':('ras_dummy_completion.v','reg_tag<=i_request_tag;',"reg_tag<={1'b0,i_request_tag[9:0]};"),
 'offset':('ras_dummy_completion.v','reg_offset<=reg_offset+2\'d1;',"reg_offset<=reg_offset+2'd2;"),
 'last':('ras_dummy_completion.v','assign o_response_last=flag_last&&o_response_valid;',"assign o_response_last=o_response_valid;"),
 'epoch':('ras_dummy_completion.v','reg_epoch<=i_request_epoch;',"reg_epoch<={EPOCH_WIDTH{1'b0}};"),
 'port':('ras_isolation_completion.v','.i_request_port(request_port)',".i_request_port(2'd0)"),
 'request_as_done':('ras_isolation_completion.v','.i_dummy_done_valid(o_dummy_done_valid)', '.i_dummy_done_valid(o_dummy_request_accepted)'),
 'late_retire':('ras_isolation_completion.v','&& !o_complete_discard',''),
 'data':('ras_dummy_completion.v',"assign o_response_data=512'd0;","assign o_response_data=o_response_valid?512'd1:512'd0;"),'done_hold':('ras_dummy_completion.v','o_done_valid&&i_done_ready','o_done_valid')}
 mutations['late_retire']=('ras_isolation_completion.v','&&!o_complete_discard','')
 for ports,capacity,sw,unit in matrix:
  faults=([k for k in mutations if k!='done_hold']if (ports,capacity,sw,unit)==(4,4,1,0)else['done_hold']if unit else[])if a.faults else[]
  for fault in [None]+faults:
   folder=stage/f'p{ports}_c{capacity}_s{sw}_u{unit}{"_"+fault if fault else ""}';folder.mkdir();ref=generate(folder/'vectors.txt',ports,capacity,sw,unit,a.epoch_width);rtls=[source/n for n in ['ras_dummy_completion.v','ras_isolation_completion.v','ras_originator_isolation.v']]
   if fault:
    fn,old,new=mutations[fault];raw=(source/fn).read_text()
    if raw.count(old)!=1:raise ValueError('fault anchor '+fault)
    target=folder/fn;target.write_text(raw.replace(old,new,1));rtls=[target if f.name==fn else f for f in rtls]
   commands={'compile':run(folder,'compile',['iverilog','-g2012','-s','dummy_tb',f'-Pdummy_tb.P={ports}',f'-Pdummy_tb.C={capacity}',f'-Pdummy_tb.SW={sw}',f'-Pdummy_tb.UNIT={unit}',f'-Pdummy_tb.E={a.epoch_width}','-o','sim.vvp',source/'dummy_tb.sv',*rtls])}
   if commands['compile']['returncode']==0:
    commands['simulate']=run(folder,'simulate',['vvp','sim.vvp','+VECTORS=vectors.txt',f'+ROWS={ref["rows"]}'])
    if not fault:
     top='ras_dummy_completion'if unit else'ras_isolation_completion';params={'EPOCH_WIDTH':a.epoch_width}if unit else{'PORTS':ports,'CAPACITY':capacity,'IS_SWITCH':sw,'EPOCH_WIDTH':a.epoch_width}
     commands['g2001']=run(folder,'g2001',['iverilog','-g2001','-s',top,*[f'-P{top}.{k}={v}'for k,v in params.items()],'-o','elab.vvp',*rtls])
     commands['lint']=run(folder,'lint',['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',top,*[f'-G{k}={v}'for k,v in params.items()],*rtls])
     commands['yosys']=run(folder,'yosys',['yosys','-Q','-T','-p','read_verilog '+' '.join(map(str,rtls))+'; chparam '+' '.join(f'-set {k} {v}'for k,v in params.items())+' '+top+'; hierarchy -check -top '+top+'; proc; opt; memory_map; check -assert; stat; write_json netlist.json'])
   log=(folder/'simulate.log').read_text()if(folder/'simulate.log').exists()else'';passed=all(c['returncode']==0 for c in commands.values())and'DUMMY_PASS'in log
   if fault:passed=commands['compile']['returncode']==0 and commands.get('simulate',{}).get('returncode')==1 and'DUMMY_CHECK'in log
   results.append({'ports':ports,'capacity':capacity,'is_switch':sw,'unit':unit,'epoch_width':a.epoch_width,'fault':fault,'reference':ref,'commands':commands,'passed':passed});print(ports,capacity,sw,unit,fault,passed,log[-160:],flush=True)
 result={'passed':all(c['passed']for c in results),'cases':results,'sources_sha256':hashes,'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest()for f in stage.rglob('*')if f.is_file()}};(stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed']else 1
if __name__=='__main__':raise SystemExit(main())

#!/usr/bin/env python3
"""Run actual native station TX and four SRAM receive/credit paths.
Run: python3 verification/upli_channels/run_station_tx.py --label NEW --kd28-root PATH [--candidate-dir PATH] [--fault FAULT].
Outputs: fresh build/verification/upli_channels/station_tx/NEW sources, simulation logs and hashes.
Next: validate full native RX/RAS/Endpoint adapters; this is two-role normal TX aggregation.
"""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
HERE=Path(__file__).resolve().parent
NAMES=('upli_station_tx.v','upli_read_response_sender.v','upli_write_response_sender.v','upli_credit_guard.v','upli_credit_return_adapter.v')
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--candidate-dir',type=Path);p.add_argument('--static',action='store_true');p.add_argument('--ports',type=int,choices=(1,2,4));p.add_argument('--capacity',type=int,choices=(4,5),default=4);p.add_argument('--credit-width',type=int,choices=range(3,17),default=4);p.add_argument('--fault',choices=('rd_tag','wr_tag','guard_bypass'))
 a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
 stage=ROOT/'build/verification/upli_channels/station_tx'/a.label;stage.mkdir(parents=True,exist_ok=False)
 manifest=ROOT/'third_party/kd28_dependency.json';deps=json.loads(manifest.read_text());sources={}
 for name,h in deps['functional_sources_sha256'].items():
  f=a.kd28_root.resolve()/name;b=f.read_bytes()
  if hashlib.sha256(b).hexdigest()!=h:raise ValueError('dependency hash mismatch: '+name)
  sources[f]=b
 for f in (ROOT/'rtl').rglob('*.v'):
  if a.candidate_dir and f.name in NAMES:continue
  sources[f]=f.read_bytes()
 if a.candidate_dir:
  for n in NAMES:
   f=a.candidate_dir.resolve()/n;sources[f]=f.read_bytes()
 files=[];hashes={};snapshots={}
 for i,(f,b) in enumerate(sources.items()):
  out=stage/'sources'/f.name;out.parent.mkdir(exist_ok=True)
  if out.exists():raise ValueError('duplicate source basename '+f.name)
  if a.fault and f.name=='upli_station_tx.v':
   old,new={'rd_tag':('.o_tag(o_rd_tag)','.o_tag()'), 'wr_tag':('.o_tag(o_wr_tag)','.o_tag()'), 'guard_bypass':('.i_check_enable(i_rstn)',".i_check_enable(1'b0)"),'req_role':('.i_beats_connected(i_originator_beats_connected)',".i_beats_connected(1'b1)")}[a.fault]
   t=b.decode()
   if old not in t:raise ValueError('fault anchor absent')
   t=t.replace(old,new) if a.fault=='guard_bypass' else t.replace(old,new,1)
   if a.fault in ('rd_tag','wr_tag'):t=t.replace('endmodule',f"assign o_{a.fault[:2]}_tag=11'd0;\nendmodule")
   b=t.encode()
  out.write_bytes(b);files.append(out.resolve());hashes[str(f)]=hashlib.sha256(sources[f]).hexdigest();snapshots[str(out.relative_to(stage))]=hashlib.sha256(b).hexdigest()
 tb=HERE/'station_tx_tb.sv';(stage/'tb.sv').write_bytes(tb.read_bytes());(stage/'runner.py').write_bytes(Path(__file__).read_bytes());(stage/'dependency.json').write_bytes(manifest.read_bytes())
 cases=[]
 for ports in ([a.ports] if a.ports else [1,2,4]):
  folder=stage/f'p{ports}';folder.mkdir();commands=[('compile',['iverilog','-g2012','-s','tb',f'-Ptb.PORTS={ports}',f'-Ptb.CAP={a.capacity}',f'-Ptb.CW={a.credit_width}','-o','sim.vvp',*[str(f) for f in files],str((stage/'tb.sv').resolve())]),('run',['vvp','sim.vvp'])];case={'ports':ports,'capacity':a.capacity,'credit_width':a.credit_width,'fault':a.fault}
  for name,cmd in commands:
   with (folder/(name+'.log')).open('w') as log:
    try:code=subprocess.run(cmd,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=180).returncode
    except subprocess.TimeoutExpired:code=124
   case[name]={'command':cmd,'exit':code}
   if name=='compile' and code:break
  log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
  case['passed']=case['compile']['exit']==0 and case.get('run',{}).get('exit')==(1 if a.fault else 0) and ('STATION_MISMATCH' if a.fault else 'STATION_PASS') in log;cases.append(case);print(ports,case['passed'],log[-450:],flush=True)
 if a.static and not a.fault:
  needed={'upli_station_tx.v','upli_request_data_sender.v','upli_read_response_sender.v','upli_write_response_sender.v','upli_burst_sender.v','upli_burst_control.v','upli_credit_bank.v','upli_request_channel.v','upli_orig_data_channel.v','upli_read_response_channel.v','upli_write_response_channel.v','upli_parity.v','upli_credit_guard.v'}
  selected=[str(f) for f in files if f.name in needed]
  if len(selected)!=len(needed):raise ValueError('incomplete static source closure')
  for ports in ([a.ports] if a.ports else [1,2,4]):
   folder=stage/f'p{ports}'
   top='upli_station_tx'
   commands={'g2001':['iverilog','-g2001','-s',top,f'-P{top}.C_NUM_PORTS={ports}',f'-P{top}.C_CREDIT_WIDTH={a.credit_width}',f'-P{top}.C_DEFAULT_CAPACITY={a.capacity}','-o','rtl.vvp',*selected],
    'lint':['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',top,f'-GC_NUM_PORTS={ports}',f'-GC_CREDIT_WIDTH={a.credit_width}',f"-GC_DEFAULT_CAPACITY={a.credit_width}'d{a.capacity}",*selected],
    'yosys':['yosys','-Q','-T','-p','read_verilog '+' '.join(selected)+f'; chparam -set C_NUM_PORTS {ports} -set C_CREDIT_WIDTH {a.credit_width} -set C_DEFAULT_CAPACITY {a.capacity} {top}; hierarchy -check -top {top}; proc; opt; check -assert; stat; write_json hierarchy.json']}
   for name,cmd in commands.items():
    with (folder/(name+'.log')).open('w') as log:
     try:code=subprocess.run(cmd,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=180).returncode
     except subprocess.TimeoutExpired:code=124
    cases.append({'ports':ports,'static':name,'exit':code,'passed':code==0,'command':cmd})
 result={'passed':all(c['passed'] for c in cases),'cases':cases,'sources_sha256':hashes,'snapshot_sha256':snapshots,'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}};(stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

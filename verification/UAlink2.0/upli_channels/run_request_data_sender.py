#!/usr/bin/env python3
"""Actual typed Request/OrigData sender integration regression.
Run: python3 verification/upli_channels/run_request_data_sender.py --label NEW --faults [--static]
Outputs: build/verification/upli_channels/request_data_sender/NEW with exact wrapper/leaf/dependency/TB snapshots and result hashes.
Next: connect the native sender to station adapters; receive and RAS remain separate work.
"""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--faults',action='store_true');p.add_argument('--static',action='store_true');a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
 stage=ROOT/'build/verification/upli_channels/request_data_sender'/a.label;stage.mkdir(parents=True,exist_ok=False)
 paths=[ROOT/'rtl/upli'/n for n in ('upli_burst_sender.v','upli_burst_control.v','upli_credit_bank.v','upli_connection_side.v')]+[ROOT/'rtl/upli/upli_request_channel.v',ROOT/'rtl/upli/upli_orig_data_channel.v',ROOT/'rtl/upli/upli_request_data_sender.v']
 parity=ROOT/'rtl/upli/upli_parity.v'
 paths.append(parity)
 sources={str(p.relative_to(ROOT)):p.read_bytes() for p in paths}
 for path,blob in sources.items():(stage/Path(path).name).write_bytes(blob)
 (stage/'tb.sv').write_bytes((HERE/'request_data_sender_tb.sv').read_bytes());(stage/'runner.py').write_bytes(Path(__file__).read_bytes())
 cases=[]
 for ports,fault in [(n,None) for n in (1,2,4)]+([(4,f) for f in ('candidate_bypass','tag_high','pool_wire')] if a.faults else []):
  name='p'+str(ports)+('_'+fault if fault else '');folder=stage/name;folder.mkdir();files=[str((stage/p.name).resolve()) for p in paths]
  if fault:
   text=(stage/'upli_request_data_sender.v').read_text();before,after={
    'candidate_bypass':('.i_valid(raw_o_req_valid)','.i_valid(i_candidate_valid)'),
    'tag_high':('.i_tag(decoded_tag)',".i_tag({1'b0,decoded_tag[9:0]})"),
    'pool_wire':('.i_pool(raw_o_req_pool)','.i_pool(~raw_o_req_pool)'),
   }[fault]
   if text.count(before)!=1:raise ValueError('fault anchor absent/ambiguous '+fault)
   altered=folder/'upli_request_data_sender.v';altered.write_text(text.replace(before,after));files=[str(altered.resolve()) if f.endswith('/upli_request_data_sender.v') else f for f in files]
  result={'ports':ports,'fault':fault}
  for phase,cmd in [('compile',['iverilog','-g2012','-s','tb',f'-Ptb.PORTS={ports}','-o','sim.vvp',*files,str((stage/'tb.sv').resolve())]),('run',['vvp','sim.vvp'])]:
   with (folder/(phase+'.log')).open('w') as log:
    try:code=subprocess.run(cmd,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=60).returncode
    except subprocess.TimeoutExpired:code=124
   result[phase]={'command':cmd,'exit':code}
   if phase=='compile' and code:break
  log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
  result['passed']=result['compile']['exit']==0 and result.get('run',{}).get('exit')==(1 if fault else 0) and ('SENDER_MISMATCH' if fault else 'SENDER_PASS') in log;cases.append(result);print(name,result['passed'],log.strip(),flush=True)
 if a.static:
  files=[str((stage/p.name).resolve()) for p in paths]
  for ports in (1,2,4):
   top='upli_request_data_sender'
   commands={'g2001':['iverilog','-g2001','-s',top,f'-P{top}.C_NUM_PORTS={ports}','-o',f'p{ports}_static.vvp',*files],
    'lint':['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',top,f'-GC_NUM_PORTS={ports}',*files],
    'yosys':['yosys','-Q','-T','-p','read_verilog '+' '.join(files)+f'; chparam -set C_NUM_PORTS {ports} {top}; hierarchy -check -top {top}; proc; opt; check -assert; stat']}
   for check,cmd in commands.items():
    with (stage/f'p{ports}_{check}.log').open('w') as log:
     try:code=subprocess.run(cmd,cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=120).returncode
     except subprocess.TimeoutExpired:code=124
    cases.append({'ports':ports,'check':check,'command':cmd,'exit':code,'passed':code==0})
 result={'passed':all(c['passed'] for c in cases),'cases':cases,'source_sha256':{p:hashlib.sha256(b).hexdigest() for p,b in sources.items()},'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}}
 (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

#!/usr/bin/env python3
"""Run: python3 verification/ip_tops/run_switch_route_table.py --label NEW --ports 3 --index-width 3 --checks.

Writes build/verification/ip_tops/switch_route_table/NEW with actual source snapshots, commands, logs and hashes.
Next: review candidate and connect active outputs only after real fabric drain.
This is a local atomic configuration service, not a standard CSR implementation.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())


def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--ports',type=int,default=4);p.add_argument('--index-width',type=int);p.add_argument('--checks',action='store_true');p.add_argument('--fault',choices=('leak','duplicate','busy'))
 a=p.parse_args();width=a.index_width or max(1,(a.ports-1).bit_length())
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe new label required')
 if not 1<=a.ports<=1024 or not 1<=width<=10 or 1<<width<a.ports:p.error('valid representable port/index configuration required')
 stage=ROOT/'build/verification/ip_tops/switch_route_table'/a.label;stage.mkdir(parents=True,exist_ok=False);(stage/'run.py').write_bytes(Path(__file__).read_bytes())
 data=(ROOT/'rtl/switch/switch_route_table.v').read_bytes();source_hash=hashlib.sha256(data).hexdigest()
 if a.fault:
  before,after={
   'leak':('assign o_route_ids=active_ids_q;','assign o_route_ids=shadow_ids_q;'),
   'duplicate':('&&i_quiescent&&!shadow_duplicate;','&&i_quiescent;'),
   'busy':('&&i_quiescent&&!shadow_duplicate;','&&!shadow_duplicate;')
  }[a.fault];text=data.decode()
  if text.count(before)!=1:raise ValueError('mutation anchor missing/ambiguous')
  data=text.replace(before,after).encode()
 (stage/'switch_route_table.v').write_bytes(data);lookup=(ROOT/'rtl/switch/switch_route_lookup.v').read_bytes();(stage/'switch_route_lookup.v').write_bytes(lookup)
 tb=Path(__file__).with_name('switch_route_table_tb.sv').read_text().replace('@@DUT_PARAMETERS@@','#(.PORTS(PORTS))' if a.index_width is None else '#(.PORTS(PORTS),.INDEX_WIDTH(INDEX_WIDTH))');(stage/'tb.sv').write_text(tb)
 result=dict(ports=a.ports,index_width=width,index_width_mode='automatic' if a.index_width is None else 'explicit',source_sha256=source_hash,lookup_sha256=hashlib.sha256(lookup).hexdigest(),fault=a.fault)
 commands=[('compile',['iverilog','-g2012','-s','tb',f'-Ptb.PORTS={a.ports}',f'-Ptb.INDEX_WIDTH={width}','-o','sim.vvp','switch_route_table.v','switch_route_lookup.v','tb.sv']),('run',['vvp','sim.vvp'])]
 if a.checks and not a.fault:
  (stage/'run.ys').write_text('\n'.join(['read_verilog switch_route_table.v',f'chparam -set PORTS {a.ports}'+('' if a.index_width is None else f' -set INDEX_WIDTH {width}')+' switch_route_table','hierarchy -check -top switch_route_table','proc','opt','memory','opt','check -assert','stat','write_json netlist.json'])+'\n')
  commands.extend([('verilog2001',['iverilog','-g2001','-s','switch_route_table',f'-Pswitch_route_table.PORTS={a.ports}',*([f'-Pswitch_route_table.INDEX_WIDTH={width}'] if a.index_width is not None else []),'-o','syntax.vvp','switch_route_table.v']),('yosys',['yosys','-Q','-T','-s','run.ys']),('verilator',['verilator','--lint-only','--language','1364-2001','-Wall','--top-module','switch_route_table',f'-GPORTS={a.ports}',*([f'-GINDEX_WIDTH={width}'] if a.index_width is not None else []),'switch_route_table.v'])])
 for name,cmd in commands:
  start=time.monotonic()
  with (stage/(name+'.log')).open('w') as log:
   try:rc=subprocess.run(cmd,cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=120).returncode
   except subprocess.TimeoutExpired:rc=124
  result[name]=dict(command=cmd,returncode=rc,seconds=round(time.monotonic()-start,3))
  if name=='compile' and rc:break
 log=(stage/'run.log').read_text() if (stage/'run.log').exists() else ''
 result['passed']=all(result.get(name,{}).get('returncode')==0 for name,_ in commands) and 'ROUTE_TABLE_PASS' in log
 if a.fault:result['passed']=result['compile']['returncode']==0 and result.get('run',{}).get('returncode')==1 and any(x in log for x in ('ROUTE_ACTIVE','ROUTE_ACK'))
 result['coverage']={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',log)}
 if (stage/'netlist.json').exists():
  net=json.loads((stage/'netlist.json').read_text());cells=[c for m in net['modules'].values() for c in m.get('cells',{}).values()];result['cells']=len(cells);result['latches']=sum('latch' in c['type'] for c in cells);result['passed']=result['passed'] and result['latches']==0
 result['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
 (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');print('PASS' if result['passed'] else 'FAIL',stage/'result.json');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

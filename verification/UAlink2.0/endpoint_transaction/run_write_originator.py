#!/usr/bin/env python3
"""Verify actual Write serializer and shared Read/Write originator.
Run: python3 verification/endpoint_transaction/run_write_originator.py --label NEW [--shell-baseline] [--faults]
Outputs snapshots, vector fixtures, compile/run logs and result.json under build/verification/endpoint_transaction/NEW.
Next inspect ownership and shared Tag diagnostics before integrating the actual transaction core.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
NAMES=['endpoint_write_originator','endpoint_request_formatter','endpoint_tag_table','endpoint_read_encode']
BASELINE='''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rstn=0;wire [1:0] ready,implemented;
endpoint_write_originator wr(.i_clk(clk),.i_rstn(rstn),.i_enable(1'b1),.i_valid(1'b1),.i_data(512'd0),.i_meta(128'd0),.o_ready(ready[0]),.o_implemented(implemented[0]));
endpoint_request_formatter fmt(.i_clk(clk),.i_rstn(rstn),.i_enable(1'b1),.i_valid(1'b1),.i_data(512'd0),.i_meta(128'd0),.o_ready(ready[1]),.o_implemented(implemented[1]));
initial begin repeat(2)@(negedge clk);rstn=1;#1;if(ready!==2'b11||implemented!==2'b11)$fatal(1,"WRITE_SHELL_UNIMPLEMENTED ready=%b implemented=%b",ready,implemented);$finish;end
endmodule
'''
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--shell-baseline',action='store_true');p.add_argument('--faults',action='store_true');a=p.parse_args()
 if not re.fullmatch(r'[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
 if a.shell_baseline and a.faults:p.error('shell baseline and implementation faults are separate')
 stage=ROOT/'build/verification/endpoint_transaction'/a.label;stage.mkdir(parents=True,exist_ok=False)
 names=NAMES[:2] if a.shell_baseline else NAMES
 sources=[ROOT/'rtl/endpoint'/f'{name}.v' for name in names]
 copies=[]
 for src in sources:
  dest=stage/src.name;shutil.copyfile(src,dest);copies.append(dest)
 shutil.copyfile(Path(__file__),stage/'runner.py')
 result={'passed':False,'sources':{str(src):sha(src) for src in sources+[Path(__file__)]},'cases':[]}
 if a.shell_baseline:cases=[('shell',BASELINE,None)]
 else:
  cases=[]
  for name in ['write_serializer','write_formatter']:
   source=ROOT/'verification/endpoint_transaction'/f'{name}_tb.sv';result['sources'][str(source)]=sha(source);cases.append((name,source.read_text(),None))
  if a.faults:
   cases.extend([('fault_tag_kind',(ROOT/'verification/endpoint_transaction/write_formatter_tb.sv').read_text(),'kind'),('fault_data_order',(ROOT/'verification/endpoint_transaction/write_serializer_tb.sv').read_text(),'data')])
 for name,tb,fault in cases:
  d=stage/name;d.mkdir();(d/'tb.sv').write_text(tb);cc=[]
  for src in copies:
   dest=d/src.name;shutil.copyfile(src,dest)
   if fault=='kind' and src.name=='endpoint_tag_table.v':
    text=dest.read_text();before='(r_is_write[response_slot]==response_is_write)'
    if text.count(before)!=1:raise ValueError('kind mutation anchor missing or ambiguous')
    dest.write_text(text.replace(before,"1'b1"))
   if fault=='data' and src.name=='endpoint_write_originator.v':
    text=dest.read_text();before='r_payload >> ({28\'d0,r_index} * 32\'d256)'
    if text.count(before)!=1:raise ValueError('data mutation anchor missing or ambiguous')
    dest.write_text(text.replace(before,"r_payload >> (({28'd0,r_index} + 32'd1) * 32'd256)"))
   cc.append(dest)
  case={'name':name}
  for phase,cmd in [('compile',['iverilog','-g2012','-s','tb','-o',str(d/'sim.vvp'),*map(str,cc),str(d/'tb.sv')]),('run',['vvp',str(d/'sim.vvp')])]:
   case[phase+'_command']=cmd
   with (d/(phase+'.log')).open('w') as log:
    try:code=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,cwd=d,timeout=180).returncode
    except subprocess.TimeoutExpired:code=124
   case[phase+'_exit']=code
   if phase=='compile' and code:break
  log=(d/'run.log').read_text() if (d/'run.log').exists() else ''
  marker='WRITE_SHELL_UNIMPLEMENTED' if a.shell_baseline else ('WRITE_KIND_MISMATCH_ACCEPTED' if fault=='kind' else 'WRITE_SERIAL_DATA' if fault=='data' else 'WRITE_TEST_PASS')
  case['passed']=case.get('compile_exit')==0 and case.get('run_exit')==(1 if a.shell_baseline or fault else 0) and marker in log
  result['cases'].append(case);print(json.dumps({k:v for k,v in case.items() if k in ['name','compile_exit','run_exit','passed']}),flush=True)
 result['passed']=all(c['passed'] for c in result['cases']);result['artifacts_sha256']={str(f.relative_to(stage)):sha(f) for f in stage.rglob('*') if f.is_file()};(stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

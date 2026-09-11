#!/usr/bin/env python3
"""Run candidate packet arbiter simulation and local static tools.
Command: python3 verification/ip_tops/run_switch_arbiter.py --label NEW [--red | --fault NAME] [--static]
Outputs: build/verification/ip_tops/switch_arbiter/NEW exact RTL/test/reference/runner snapshots, vectors, logs, result.json and hashes.
Next: review raw-selection gating before the parent integrates the candidate in production fabric.
"""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
from switch_arbiter_reference import vectors,pack
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
TESTS=Path(__file__).resolve().parent
RED='''module switch_arbiter #(parameter PORTS=4)(input wire i_clk,i_rstn,input wire [PORTS-1:0] i_valid,input wire [PORTS*PORTS-1:0] i_route_match,input wire [PORTS-1:0] i_last,i_ready,output wire [PORTS*PORTS-1:0] o_select,output wire [PORTS-1:0] o_owned);assign o_owned={PORTS{1'b0}};assign o_select={PORTS*PORTS{1'b0}};endmodule\n'''

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--red',action='store_true');p.add_argument('--static',action='store_true');p.add_argument('--ports',default=None)
 p.add_argument('--fault',choices=['ready_gate','stall_unlocked','early_last','route_release','rr_stuck','reset_unmasked','owned_as_valid']);a=p.parse_args()
 if not re.fullmatch(r'[A-Za-z0-9_-]+',a.label):p.error('safe new label required')
 if a.red and (a.static or a.fault):p.error('red is a standalone fail-closed baseline')
 ports=[int(v) for v in a.ports.split(',')] if a.ports else ([3] if a.fault else [1,2,3,4,5])
 if not ports or any(v not in (1,2,3,4,5) for v in ports):p.error('verified ports are 1,2,3,4,5')
 out=ROOT/'build/verification/ip_tops/switch_arbiter'/a.label;out.mkdir(parents=True,exist_ok=False)
 source=RED.encode() if a.red else (ROOT/'rtl/switch/switch_arbiter.v').read_bytes();original_hash=hashlib.sha256(source).hexdigest()
 mutations={
  'owned_as_valid':(b'o_owned = i_rstn ? locked_q :',b'o_owned = i_rstn ? (locked_q & i_valid) :'),
  'ready_gate':(b'if (i_rstn) begin',b'if (i_rstn && i_ready[egress]) begin'),
  'stall_unlocked':(b'if (selected[state_port] >= 0 &&',b'if (i_ready[state_port] && selected[state_port] >= 0 &&'),
  'early_last':(b'if (i_ready[state_port] && i_last[selected[state_port]]) begin',b'if (i_last[selected[state_port]]) begin'),
  'route_release':(b'i_route_match[selected[state_port]*PORTS+state_port]) begin',b"1'b1) begin"),
  'rr_stuck':(b'round_robin_q[state_port] <= selected[state_port] + 1;',b'round_robin_q[state_port] <= 0;'),
  'reset_unmasked':(b'if (i_rstn) begin',b"if (1'b1) begin"),
 }
 if a.fault:
  before,after=mutations[a.fault]
  if source.count(before)!=1:raise ValueError('mutation anchor absent or ambiguous')
  source=source.replace(before,after)
 (out/'switch_arbiter.v').write_bytes(source)
 for name in ['switch_arbiter_tb.sv','switch_arbiter_reference.py','run_switch_arbiter.py']:(out/name).write_bytes((TESTS/name).read_bytes())
 result={'passed':True,'ports':ports,'red':a.red,'fault':a.fault,'original_rtl_sha256':original_hash,'compiled_rtl_sha256':hashlib.sha256(source).hexdigest(),'cases':{}}
 def call(cmd,folder,name):
  with (folder/(name+'.log')).open('w') as log:
   try:return subprocess.run(cmd,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=90).returncode
   except subprocess.TimeoutExpired:return 124
 for port in ports:
  folder=out/f'p{port}';folder.mkdir();rows,coverage=vectors(port)
  (folder/'vectors.hex').write_text(''.join(f'{pack(row,port):032x}\n' for row in rows));(folder/'vectors.json').write_text(json.dumps(rows,indent=2)+'\n')
  command=['iverilog','-g2012','-s','tb',f'-Ptb.PORTS={port}',f'-Ptb.COUNT={len(rows)}','-o',str(folder/'sim.vvp'),str(out/'switch_arbiter.v'),str(out/'switch_arbiter_tb.sv')]
  case={'coverage':coverage,'rows':len(rows),'compile_command':command,'compile_exit':call(command,folder,'compile')}
  if case['compile_exit']==0:
   case['run_command']=['vvp',str(folder/'sim.vvp')];case['run_exit']=call(case['run_command'],folder,'run')
  log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
  case['passed']=case['compile_exit']==0 and case.get('run_exit')==(1 if a.red or a.fault else 0) and (any(marker in log for marker in ('ARBITER_SELECTION','ARBITER_READY_DEPENDENCE','ARBITER_OWNERSHIP')) if a.red or a.fault else 'ARBITER_PASS' in log)
  if a.static:
   commands={
    'g2001':['iverilog','-g2001','-s','switch_arbiter',f'-Pswitch_arbiter.PORTS={port}','-o',str(folder/'rtl.vvp'),str(out/'switch_arbiter.v')],
    'strictlint':['verilator','--lint-only','--Wall','--language','1364-2001','--top-module','switch_arbiter',f'-GPORTS={port}',str(out/'switch_arbiter.v')],
    'yosys':['yosys','-Q','-T','-p',f'read_verilog {out / "switch_arbiter.v"}; chparam -set PORTS {port} switch_arbiter; hierarchy -check -top switch_arbiter; proc; opt; check -assert; stat'],
   }
   case['static']={name:{'command':cmd,'exit':call(cmd,folder,name)} for name,cmd in commands.items()};case['passed']&=all(item['exit']==0 for item in case['static'].values())
  result['cases'][str(port)]=case;result['passed']&=case['passed']
 result['artifacts_sha256']={str(f.relative_to(out)):hashlib.sha256(f.read_bytes()).hexdigest() for f in out.rglob('*') if f.is_file()}
 (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'passed':result['passed'],'cases':{k:{kk:vv for kk,vv in v.items() if kk in ('rows','compile_exit','run_exit','passed','static')} for k,v in result['cases'].items()}}));return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

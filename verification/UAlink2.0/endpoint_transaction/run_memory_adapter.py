#!/usr/bin/env python3
"""Verify endpoint_memory_adapter. Run: python3 verification/endpoint_transaction/run_memory_adapter.py --label NEW [--faults] [--static]."""
import argparse,hashlib,json,shutil,subprocess
from pathlib import Path
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve()); HERE=Path(__file__).resolve().parent

def command(folder,name,argv):
 p=subprocess.run([str(x) for x in argv],capture_output=True,text=True)
 (folder/(name+'.log')).write_text(p.stdout+p.stderr)
 return {'argv':[str(x) for x in argv],'returncode':p.returncode}

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--rtl',type=Path,default=ROOT/'rtl/endpoint/endpoint_memory_adapter.v');p.add_argument('--faults',action='store_true');p.add_argument('--static',action='store_true');a=p.parse_args()
 stage=ROOT/'build/verification/endpoint_transaction/memory_adapter'/a.label;stage.mkdir(parents=True,exist_ok=False);source=stage/'source';source.mkdir()
 rtl=source/'endpoint_memory_adapter.v';tb=source/'endpoint_memory_adapter_tb.sv';shutil.copy2(a.rtl.resolve(),rtl);shutil.copy2(HERE/'endpoint_memory_adapter_tb.sv',tb)
 original=rtl.read_text();tests=[]
 cases={'normal':None}
 if a.faults:cases.update({
  'backend_token':("assign o_backend_token=o_backend_valid?r_token:{TOKEN_WIDTH{1'b0}};","assign o_backend_token=o_backend_valid?{TOKEN_WIDTH{1'b0}}:{TOKEN_WIDTH{1'b0}};"),
  'backend_station':("assign o_backend_station=o_backend_valid?r_station:{STATION_WIDTH{1'b0}};","assign o_backend_station=o_backend_valid?{STATION_WIDTH{1'b0}}:{STATION_WIDTH{1'b0}};"),
  'backend_payload':("assign o_backend_payload=o_backend_valid?r_payload:184'd0;","assign o_backend_payload=184'd0;"),
  'completion_status':("assign o_completion_token=o_completion_valid?r_token:{TOKEN_WIDTH{1'b0}};assign o_completion_status=o_completion_valid?r_status:4'd0;","assign o_completion_token=o_completion_valid?r_token:{TOKEN_WIDTH{1'b0}};assign o_completion_status=4'd0;"),
  'completion_data':("assign o_completion_data=o_completion_valid?r_result_data:2048'd0;","assign o_completion_data=2048'd0;"),
  'early_final':("if((r_state==S_FINAL_WAIT)&&(i_final_token==r_token))r_state<=S_RELEASE;","if((r_state!=S_IDLE)&&(i_final_token==r_token))r_state<=S_RELEASE;"),
  'completion_release':("if(completion_fire)r_state<=S_FINAL_WAIT;","if(completion_fire)r_state<=S_RELEASE;"),
  'reset_busy':("r_state<=S_IDLE;r_token","r_state<=S_COMMAND;r_token")})
 for name,mutation in cases.items():
  folder=stage/name;folder.mkdir();target=rtl
  if mutation:
   old,new=mutation
   if original.count(old)!=1:raise RuntimeError(f'{name}: mutation anchor count {original.count(old)}')
   target=folder/'endpoint_memory_adapter.v';target.write_text(original.replace(old,new))
  exe=folder/'sim.vvp';compile_result=command(folder,'compile',['iverilog','-g2012','-s','endpoint_memory_adapter_tb','-o',exe,tb,target])
  run_result=command(folder,'run',['vvp',exe]) if compile_result['returncode']==0 else {'argv':[],'returncode':127}
  passed=compile_result['returncode']==0 and run_result['returncode']==0 and 'MEMORY_ADAPTER_PASS' in (folder/'run.log').read_text()
  expected=not mutation;tests.append({'name':name,'passed':passed==expected,'healthy_passed':passed,'expected_healthy':expected,'commands':{'compile':compile_result,'run':run_result}});print(name,passed==expected,flush=True)
 static={}
 if a.static:
  static['g2001']=command(stage,'g2001',['iverilog','-g2001','-s','endpoint_memory_adapter','-o',stage/'g2001.vvp',rtl])
  static['lint']=command(stage,'lint',['verilator','--lint-only','--language','1364-2001','-Wall','--top-module','endpoint_memory_adapter',rtl])
  static['yosys']=command(stage,'yosys',['yosys','-Q','-T','-p',f'read_verilog {rtl}; hierarchy -check -top endpoint_memory_adapter; proc; opt; check -assert; stat'])
  for width in (0,33):
   static[f'invalid_token_{width}']=command(stage,f'invalid_token_{width}',['iverilog','-g2001','-s','endpoint_memory_adapter',f'-Pendpoint_memory_adapter.TOKEN_WIDTH={width}','-o',stage/f'invalid_{width}.vvp',rtl])
 passed=all(x['passed'] for x in tests) and all((v['returncode']==0)==(not k.startswith('invalid_')) for k,v in static.items())
 result={'passed':passed,'tests':tests,'static':static,'rtl_sha256':hashlib.sha256(rtl.read_bytes()).hexdigest(),'tb_sha256':hashlib.sha256(tb.read_bytes()).hexdigest(),'scope':'single outstanding backend lifecycle; context release only after explicit final response retirement'}
 (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if passed else 1
if __name__=='__main__':raise SystemExit(main())

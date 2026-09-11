#!/usr/bin/env python3
"""Run: python3 verification/upli_channels/run_endpoint_context_top.py --label NEW --kd28-root PATH [--ports 1|2|4] [--static].
Artifacts: ROOT/build/verification/upli_channels/endpoint_context_top/NEW snapshots/logs/hashes.
Next: connect real request/response contexts and backend execution; full RAS remains open.
"""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
TOP='upli_endpoint_ip_top'
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--ports',type=int,choices=(1,2,4));p.add_argument('--tl-mode',type=int,choices=(0,1),default=0);p.add_argument('--static',action='store_true');p.add_argument('--legacy',action='store_true');p.add_argument('--fault',choices=('admission','tag','release','reset'))
 a=p.parse_args();a.red=False;enable=0 if a.legacy else 1
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
 stage=ROOT/'build/verification/upli_channels/endpoint_context_top'/a.label;stage.mkdir(parents=True,exist_ok=False);src=stage/'source';src.mkdir()
 deps=json.loads((ROOT/'third_party/kd28_dependency.json').read_text())['functional_sources_sha256']
 external_paths={(a.kd28_root.resolve()/name).resolve():name for name in deps}
 paths=[ROOT/'rtl/endpoint/endpoint_memory_adapter.v']+list((ROOT/'rtl/upli').glob('*.v'))+[a.kd28_root.resolve()/n for n in deps]
 paths=[f for f in paths if f.stem not in {TOP,'upli_endpoint_native_rx_path'}]+[ROOT/'rtl/upli/upli_endpoint_native_rx_path.v',ROOT/'rtl/upli'/(TOP+'.v')]
 hashes={};files=[]
 for f in paths+[HERE/('endpoint_context_top_legacy_tb.sv' if a.legacy else 'endpoint_context_top_tb.sv'),Path(__file__),ROOT/'third_party/kd28_dependency.json']:
  b=f.read_bytes();h=hashlib.sha256(b).hexdigest()
  resolved=f.resolve()
  if resolved in external_paths and h!=deps[external_paths[resolved]]:raise ValueError('dependency changed '+str(f))
  hashes[str(f)]=h;target=src/(TOP+'.v' if f.name=='red_stub.v' else f.name)
  if target.exists():raise ValueError('collision '+target.name)
  if a.fault and f.stem==TOP:
   edits={
    'admission':[(".i_request_ready(context_bridge_ready)",".i_request_ready(i_rx_request_ready)")],
    'tag':[(".i_request_payload(o_rx_request_payload)",".i_request_payload(o_rx_request_payload ^ (184'd1 << 97))")],
    'release':[(".i_release_valid(context_release_valid)",".i_release_valid(1'b0)")],
    'reset':[(".i_rstn(context_rstn)",".i_rstn(i_rstn)")]
   }[a.fault]
   t=b.decode()
   for old,new in edits:
    if old not in t:raise ValueError('missing fault anchor '+old)
    t=t.replace(old,new,1)
   b=t.encode()
  target.write_bytes(b)
  if f in paths:files.append(target)
 static=[];lint=[]
 needed={TOP,'endpoint_memory_adapter','upli_endpoint_request_context','upli_endpoint_response_collector','upli_endpoint_native_rx_path','upli_station_tx','upli_native_rx_burst_monitor','upli_connection_side','upli_rx_role_fault_controller','upli_credit_guard','upli_request_data_sender','upli_burst_sender','upli_burst_control','upli_credit_bank','upli_request_channel','upli_orig_data_channel','upli_read_response_sender','upli_write_response_sender','upli_read_response_channel','upli_write_response_channel','upli_endpoint_request_bridge','upli_receive_tdm_monitor','upli_native_rx_channel','upli_native_rx_protection','upli_ordered_receive_channel','upli_receive_channel','upli_receive_storage','upli_receive_fifo','upli_credit_initializer','upli_credit_return_queue','upli_credit_return_adapter','upli_parity'}
 for f in files:
  if f.stem in needed or f.name in {Path(n).name for n in deps}:static.append(f)
 if a.static:
  split=stage/'lint_cells';split.mkdir();split_info={}
  for f in static:
   if f.name!='kd28_sram_cells.v':lint.append(f);continue
   text=f.read_text();blocks=list(re.finditer(r'(?ms)^module\s+(\w+)\b.*?^endmodule[^\n]*(?:\n|$)',text));header=text[:blocks[0].start()];footer=text[blocks[-1].end():]
   for x,y in zip(blocks,blocks[1:]):
    if text[x.end():y.start()].strip():raise ValueError('unhandled inter-module content')
   for m in blocks:
    target=split/(m.group(1)+'.v');target.write_text(header+m.group(0)+footer);lint.append(target);split_info[target.name]={'source_sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'body_sha256':hashlib.sha256(m.group(0).encode()).hexdigest()}
  (stage/'lint_split.json').write_text(json.dumps(split_info,indent=2)+'\n')
 def run(folder,name,cmd):
  cmd=[str(x) for x in cmd];start=time.monotonic()
  with (folder/(name+'.log')).open('w') as log:
   try:rc=subprocess.run(cmd,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=180).returncode
   except subprocess.TimeoutExpired:rc=124
  return {'command':cmd,'exit':rc,'seconds':round(time.monotonic()-start,3)}
 results=[]
 for ports in ([a.ports] if a.ports else [1,2,4]):
  folder=stage/f'p{ports}';folder.mkdir();commands={}
  commands['compile']=run(folder,'compile',['iverilog','-g2012','-s','tb',f'-Ptb.PORTS={ports}',f'-Ptb.TL={a.tl_mode}','-o','sim.vvp',*files,src/('endpoint_context_top_legacy_tb.sv' if a.legacy else 'endpoint_context_top_tb.sv')])
  if commands['compile']['exit']==0:commands['run']=run(folder,'run',['vvp','sim.vvp'])
  log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
  passed=commands['compile']['exit']==0 and commands.get('run',{}).get('exit')==(1 if a.fault or a.red else 0) and ('IP_TOP_MISMATCH' if a.fault or a.red else ('IP_TOP_PASS' if a.legacy else 'CONTEXT_TOP_PASS')) in log
  structure={}
  if a.static and not a.fault and not a.red and passed:
   for name,cmd in {
    'g2001':['iverilog','-g2001','-s',TOP,f'-P{TOP}.C_NUM_PORTS={ports}',f'-P{TOP}.C_IS_TL={a.tl_mode}',f'-P{TOP}.C_REQUEST_CONTEXT_ENABLE={enable}','-o','rtl.vvp',*static],
    'lint':['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',TOP,f'-GC_NUM_PORTS={ports}',f'-GC_IS_TL={a.tl_mode}',f'-GC_REQUEST_CONTEXT_ENABLE={enable}',*lint],
    'yosys':['yosys','-Q','-T','-p','read_verilog '+' '.join(map(str,static))+f'; chparam -set C_NUM_PORTS {ports} -set C_IS_TL {a.tl_mode} -set C_REQUEST_CONTEXT_ENABLE {enable} {TOP}; hierarchy -check -top {TOP}; proc; opt; check -assert; stat; write_json hierarchy.json']}.items():commands[name]=run(folder,name,cmd)
   passed=passed and all(x['exit']==0 for x in commands.values())
   if (folder/'hierarchy.json').exists():
    modules=json.loads((folder/'hierarchy.json').read_text())['modules'];hier={}
    def visit(n):
     m=modules[n];kind=m.get('attributes',{}).get('hdlname',n).split()[0].lstrip('\\');hier[kind]=hier.get(kind,0)+1
     for c in m.get('cells',{}).values():
      if c['type'] in modules:visit(c['type'])
    visit(TOP);structure={'hierarchy':hier,'latches':sum('latch' in c['type'].lower() for m in modules.values() for c in m.get('cells',{}).values())}
    passed=passed and hier.get('upli_endpoint_request_context',0)==enable and structure['latches']==0 and all(hier.get(k)==v for k,v in {'upli_native_rx_channel':4,'upli_receive_tdm_monitor':1,'upli_native_rx_burst_monitor':1,'upli_endpoint_request_bridge':1,'upli_ordered_receive_channel':4,'upli_parity':36,'upli_endpoint_response_collector':1,'upli_station_tx':1,'upli_credit_bank':4,'upli_connection_side':2,'upli_rx_role_fault_controller':1}.items())
  results.append({'ports':ports,'tl_mode':a.tl_mode,'passed':passed,'commands':commands,'structure':structure});print(ports,passed,log[-500:],flush=True)
 result={'passed':all(c['passed'] for c in results),'fault':a.fault,'red':a.red,'legacy':a.legacy,'cases':results,'sources_sha256':hashes,'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}}
 (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

#!/usr/bin/env python3
"""Run production Endpoint native RX integration verification.

Run: python3 verification/ip_tops/run_endpoint_native_rx_path.py --label NEW
     --kd28-root /explicit/OverFlow [--ports 1|2|4] [--static]
Artifacts: build/verification/ip_tops/endpoint_native_rx_path/NEW.
Next: connect the trusted response heads to the Endpoint response collector.
"""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path

ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
HERE=Path(__file__).resolve().parent
TOP='upli_endpoint_native_rx_path'

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--ports',type=int,choices=(1,2,4));p.add_argument('--static',action='store_true');p.add_argument('--fault',choices=('tag','credit_pool','tdm','drop_reset'))
 a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
 stage=ROOT/'build/verification/ip_tops/endpoint_native_rx_path'/a.label;stage.mkdir(parents=True,exist_ok=False);src=stage/'source';src.mkdir()
 deps=json.loads((ROOT/'third_party/kd28_dependency.json').read_text())['functional_sources_sha256']
 external_paths={(a.kd28_root.resolve()/name).resolve():name for name in deps}
 top_rtl=ROOT/'rtl/upli'/f'{TOP}.v'
 tb=HERE/'endpoint_native_rx_path_tb.sv'
 interface=HERE/'endpoint_native_rx_path_interface.json'
 paths=list((ROOT/'rtl/upli').glob('*.v'))+[a.kd28_root.resolve()/n for n in deps]
 paths=[f for f in paths if f.stem!=TOP]+[top_rtl]
 hashes={};files=[]
 for f in paths+[tb,Path(__file__),interface,ROOT/'third_party/kd28_dependency.json']:
  b=f.read_bytes();h=hashlib.sha256(b).hexdigest()
  resolved=f.resolve()
  if resolved in external_paths and h!=deps[external_paths[resolved]]:raise ValueError('dependency changed '+str(f))
  hashes[str(f)]=h;target=src/f.name
  if target.exists():raise ValueError('collision '+target.name)
  if a.fault and (f.stem==TOP and a.fault!='credit_pool' or f.stem=='upli_native_rx_channel' and a.fault=='credit_pool'):
   old,new={'tag':('.o_request_payload(o_request_payload)', '.o_request_payload()'), 'credit_pool':('.i_credit_pool(raw_credit_pool)', '.i_credit_pool(raw_credit_pool & ~raw_credit_done)'), 'tdm':('.i_rd_port(i_rd_port)', ".i_rd_port(2'd0)"), 'drop_reset':('assign bridge_rstn=i_rstn && !i_completer_drop;', 'assign bridge_rstn=i_rstn;')}[a.fault]
   t=b.decode()
   if old not in t:raise ValueError('missing fault anchor')
   t=t.replace(old,new,1)
   if a.fault=='tag':t=t.replace('endmodule',"assign o_request_payload=184'd0;\nendmodule")
   b=t.encode()
  target.write_bytes(b)
  if f in paths:files.append(target)
 static=[];lint=[]
 needed={TOP,'upli_endpoint_request_bridge','upli_receive_tdm_monitor','upli_native_rx_channel','upli_native_rx_protection','upli_ordered_receive_channel','upli_receive_channel','upli_receive_storage','upli_receive_fifo','upli_credit_initializer','upli_credit_return_queue','upli_credit_return_adapter','upli_parity'}
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
  commands['compile']=run(folder,'compile',['iverilog','-g2012','-s','tb',f'-Ptb.PORTS={ports}','-o','sim.vvp',*files,src/tb.name])
  if commands['compile']['exit']==0:commands['run']=run(folder,'run',['vvp','sim.vvp'])
  log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
  passed=commands['compile']['exit']==0 and commands.get('run',{}).get('exit')==(1 if a.fault else 0) and ('PATH_MISMATCH' if a.fault else 'PATH_PASS') in log
  structure={}
  if a.static and not a.fault and passed:
   for name,cmd in {
    'g2001':['iverilog','-g2001','-s',TOP,f'-P{TOP}.C_NUM_PORTS={ports}','-o','rtl.vvp',*static],
    'lint':['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',TOP,f'-GC_NUM_PORTS={ports}',*lint],
    'yosys':['yosys','-Q','-T','-p','read_verilog '+' '.join(map(str,static))+f'; chparam -set C_NUM_PORTS {ports} {TOP}; hierarchy -check -top {TOP}; proc; opt; check -assert; stat; write_json hierarchy.json']}.items():commands[name]=run(folder,name,cmd)
   passed=passed and all(x['exit']==0 for x in commands.values())
   if (folder/'hierarchy.json').exists():
    modules=json.loads((folder/'hierarchy.json').read_text())['modules'];hier={}
    def visit(n):
     m=modules[n];kind=m.get('attributes',{}).get('hdlname',n).split()[0].lstrip('\\');hier[kind]=hier.get(kind,0)+1
     for c in m.get('cells',{}).values():
      if c['type'] in modules:visit(c['type'])
    visit(TOP);structure={'hierarchy':hier,'latches':sum('latch' in c['type'].lower() for m in modules.values() for c in m.get('cells',{}).values())}
    passed=passed and structure['latches']==0 and all(hier.get(k)==v for k,v in {'upli_native_rx_channel':4,'upli_receive_tdm_monitor':1,'upli_endpoint_request_bridge':1,'upli_ordered_receive_channel':4,'upli_parity':20}.items())
  results.append({'ports':ports,'passed':passed,'commands':commands,'structure':structure});print(ports,passed,log[-500:],flush=True)
 result={'passed':all(c['passed'] for c in results),'fault':a.fault,'cases':results,'sources_sha256':hashes,'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}}
 (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

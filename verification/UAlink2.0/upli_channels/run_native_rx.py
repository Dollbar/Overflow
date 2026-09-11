#!/usr/bin/env python3
"""Run: python3 verification/upli_channels/run_native_rx.py --label NEW --kd28-root PATH.
Output: ROOT/build/verification/upli_channels/native_rx/NEW sources/vectors/logs/hashes.
--candidate-dir explicitly selects isolated RTL. Next integrate the role fault owner and assembler.
"""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path
from native_rx_reference import cases,WIDTHS
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve());HERE=Path(__file__).resolve().parent
NAMES=('upli_native_rx_channel.v','upli_native_rx_protection.v')
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--kd28-root',required=True,type=Path);p.add_argument('--project-root',type=Path,default=ROOT);p.add_argument('--candidate-dir',type=Path);p.add_argument('--kind',type=int,choices=range(4));p.add_argument('--ports',type=int,choices=(1,2,4));p.add_argument('--static',action='store_true');p.add_argument('--fault',choices=('control_gate','poison','byte_enable','credit_pool','head_retire','drop_gate'))
 a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
 stage=ROOT/'build/verification/upli_channels/native_rx'/a.label;stage.mkdir(parents=True,exist_ok=False)
 source=stage/'source';source.mkdir();hashes={};compiled=[]
 project=a.project_root.resolve();manifest=project/'third_party/kd28_dependency.json';deps=json.loads(manifest.read_text())['functional_sources_sha256']
 paths=[f for f in (project/'rtl').rglob('*.v') if f.name not in NAMES]
 paths += [(a.candidate_dir.resolve()/n if a.candidate_dir else project/'rtl/upli'/n) for n in NAMES]
 paths += [a.kd28_root.resolve()/n for n in deps]
 for f in paths+[HERE/'native_rx_tb.sv',HERE/'native_rx_reference.py',Path(__file__),manifest]:
  if not f.exists():continue
  b=f.read_bytes()
  if f.is_relative_to(a.kd28_root.resolve()) and str(f.relative_to(a.kd28_root.resolve())) in deps and hashlib.sha256(b).hexdigest()!=deps[str(f.relative_to(a.kd28_root.resolve()))]:raise ValueError('KD28 hash mismatch')
  target=source/f.name
  if target.exists():raise ValueError('basename collision '+f.name)
  target.write_bytes(b);hashes[str(f)]=hashlib.sha256(b).hexdigest()
  if f in paths:compiled.append(target)
 if a.fault:
  target=source/(NAMES[0] if a.fault in ('control_gate','credit_pool','head_retire','drop_gate') else NAMES[1]);code=target.read_text()
  old,new={'control_gate':('o_control_error || o_auth_error',"1'b0 || o_auth_error"),'poison':('i_payload[0] | detected_data', 'i_payload[0]'), 'byte_enable':('.i_byte_enable(byte_enable)',".i_byte_enable(64'd0)"),'credit_pool':('.i_credit_pool(raw_credit_pool)',".i_credit_pool(4'd0)"),'head_retire':('.i_consumer_ready(i_consumer_ready && flag_operate)', '.i_consumer_ready(i_consumer_ready)'),'drop_gate':('!i_drop',"1'b1")}[a.fault]
  if old not in code:raise ValueError('fault anchor absent')
  target.write_text(code.replace(old,new,1))
 static_files=[];lint_files=[];split_manifest={}
 needed={'upli_native_rx_channel','upli_native_rx_protection','upli_ordered_receive_channel','upli_receive_channel','upli_receive_storage','upli_receive_fifo','upli_credit_initializer','upli_credit_return_queue','upli_credit_return_adapter','upli_parity'}
 dependency_basenames={Path(n).name for n in deps}
 for f in compiled:
  if f.stem in needed or f.name in dependency_basenames:static_files.append(f)
 if a.static:
  # Exact external multi-module bodies are split only for filename lint; no HDL statement changes.
  split=stage/'lint_cells';split.mkdir()
  for f in static_files:
   if f.name!='kd28_sram_cells.v':lint_files.append(f);continue
   text=f.read_text();blocks=list(re.finditer(r'(?ms)^module\s+(\w+)\b.*?^endmodule[^\n]*(?:\n|$)',text))
   if not blocks:raise ValueError('external cells parser found no module')
   header=text[:blocks[0].start()];footer=text[blocks[-1].end():]
   for previous,current in zip(blocks,blocks[1:]):
    if text[previous.end():current.start()].strip():raise ValueError('inter-module content cannot be omitted')
   for match in blocks:
    target=split/(match.group(1)+'.v');target.write_text(header+match.group(0)+footer);lint_files.append(target)
    split_manifest[target.name]={'source':str(f),'source_sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'module_body_sha256':hashlib.sha256(match.group(0).encode()).hexdigest(),'output_sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
  (stage/'lint_split_manifest.json').write_text(json.dumps(split_manifest,indent=2)+'\n')
 results=[]
 def run(folder,name,cmd):
  start=time.monotonic()
  with (folder/(name+'.log')).open('w') as log:
   try:rc=subprocess.run([str(c) for c in cmd],cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=90).returncode
   except subprocess.TimeoutExpired:rc=124
  return {'command':[str(c) for c in cmd],'returncode':rc,'seconds':round(time.monotonic()-start,3)}
 for kind in ([a.kind] if a.kind is not None else range(4)):
  for ports in ([a.ports] if a.ports else [1,2,4]):
   folder=stage/f'k{kind}_p{ports}';folder.mkdir();ref=cases(folder/'vectors.txt',kind,ports);commands={}
   commands['compile']=run(folder,'compile',['iverilog','-g2012','-s','native_rx_tb',f'-Pnative_rx_tb.KIND={kind}',f'-Pnative_rx_tb.PORTS={ports}','-o','sim.vvp',source/'native_rx_tb.sv',*compiled])
   if commands['compile']['returncode']==0:commands['simulate']=run(folder,'simulate',['vvp','sim.vvp','+VECTORS=vectors.txt',f'+ROWS={ref["rows"]}'])
   if a.static and not a.fault and commands.get('simulate',{}).get('returncode')==0:
    top='upli_native_rx_channel'
    for name,cmd in {
     'g2001':['iverilog','-g2001','-s',top,f'-P{top}.CHANNEL_KIND={kind}',f'-P{top}.C_NUM_PORTS={ports}','-o','elab.vvp',*static_files],
     'lint':['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',top,f'-GCHANNEL_KIND={kind}',f'-GC_NUM_PORTS={ports}',*lint_files],
     'yosys':['yosys','-Q','-T','-p','read_verilog '+' '.join(str(f) for f in static_files)+f'; chparam -set CHANNEL_KIND {kind} -set C_NUM_PORTS {ports} {top}; hierarchy -check -top {top}; proc; opt; check -assert; stat; write_json netlist.json']}.items():commands[name]=run(folder,name,cmd)
   log=(folder/'simulate.log').read_text() if (folder/'simulate.log').exists() else ''
   passed=all(c['returncode']==0 for c in commands.values()) and 'NATIVE_RX_PASS' in log
   if a.fault:passed=commands['compile']['returncode']==0 and commands.get('simulate',{}).get('returncode')==1 and 'RX_' in log
   structure={}
   if (folder/'netlist.json').exists():
    modules=json.loads((folder/'netlist.json').read_text())['modules'];hierarchy={}
    def visit(name):
     m=modules[name];kind_name=m.get('attributes',{}).get('hdlname',name).split()[0].lstrip('\\');hierarchy[kind_name]=hierarchy.get(kind_name,0)+1
     for cell in m.get('cells',{}).values():
      if cell['type'] in modules:visit(cell['type'])
    visit('upli_native_rx_channel')
    structure={'hierarchy':hierarchy,'latches':sum('latch' in c['type'].lower() for m in modules.values() for c in m.get('cells',{}).values())}
    passed=passed and structure['latches']==0 and all(hierarchy.get(n)==count for n,count in {'upli_native_rx_channel':1,'upli_native_rx_protection':2,'upli_ordered_receive_channel':1,'upli_receive_channel':1,'upli_credit_return_adapter':1,'upli_credit_return_queue':1,'upli_parity':5}.items())
   results.append({'kind':kind,'ports':ports,'reference':ref,'commands':commands,'structure':structure,'passed':passed});print(kind,ports,passed,log[-200:],flush=True)
 result={'passed':all(c['passed'] for c in results),'cases':results,'sources_sha256':hashes,'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}}
 (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

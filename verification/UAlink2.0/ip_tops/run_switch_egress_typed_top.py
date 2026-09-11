#!/usr/bin/env python3
"""Run --label NEW [--rtl PATH --scheduler PATH --project-root ROOT] [--faults].
Artifacts: ROOT/build/verification/ip_tops/switch_egress_typed_top/NEW.
Next connect the local physical egress stream to the confirmed TL link profile.
"""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path
HERE=Path(__file__).resolve().parent;ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--rtl',type=Path,default=ROOT/'rtl/switch/ualink_switch_top.v');p.add_argument('--scheduler',type=Path,default=ROOT/'rtl/switch/switch_egress_scheduler.v');p.add_argument('--project-root',type=Path,default=ROOT);p.add_argument('--faults',action='store_true');a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('fresh safe label')
 stage=ROOT/'build/verification/ip_tops/switch_egress_typed_top'/a.label;stage.mkdir(parents=True,exist_ok=False);source=stage/'source';source.mkdir();hashes={};files=[]
 paths=[a.rtl.resolve(),a.scheduler.resolve(),ROOT/'rtl/switch/switch_egress_typed_pipeline.v']+[a.project_root.resolve()/'rtl/switch'/n for n in ['switch_route_lookup.v','switch_route_table.v','switch_arbiter.v','switch_fabric.v','switch_egress_pipeline.v','switch_egress_repack.v','switch_egress_vc_queues.v','switch_egress_packet_queue.v','switch_credit_reservation.v']]+[a.project_root.resolve()/'rtl/upli/upli_receive_fifo.v']
 inventory=json.loads((a.project_root/'config/ip_module_inventory.json').read_text())
 paths += [a.project_root/m['path'] for m in inventory['modules'] if m['status']=='planned' and 'switch' in m['roles']]
 paths += list((a.project_root/'rtl/scaffold').rglob('*switch*.v'))
 for f in paths+[Path(__file__),HERE/'switch_egress_typed_top_tb.sv']:
  blob=f.read_bytes();target=source/f.name
  if target.exists():raise ValueError('source collision')
  target.write_bytes(blob);hashes[str(f)]=hashlib.sha256(blob).hexdigest()
  if f in paths:files.append(target)
 # Scope pre-existing scaffold-only diagnostics to their exact source files. New datapath RTL gets no waiver.
 waiver=source/'existing_scaffold.vlt'
 lines=['`verilator_config']
 for m in inventory['modules']:
  if m['status']=='planned' and 'switch' in m['roles']:
   lines.append('lint_off -rule UNUSEDSIGNAL -file "'+str(source/Path(m['path']).name)+'"')
 lines.append('lint_off -rule PINCONNECTEMPTY -file "'+str(source/'ualink_switch_scaffold.v')+'"')
 lines.append('lint_off -rule UNUSEDSIGNAL -file "'+str(source/'ualink_switch_scaffold.v')+'"')
 waiver.write_text('\n'.join(lines)+'\n')
 rtl=source/'ualink_switch_top.v';results=[]
 def run(folder,name,cmd):
  begin=time.monotonic()
  with (folder/(name+'.log')).open('w') as log:
   try:rc=subprocess.run([str(c) for c in cmd],cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=60).returncode
   except subprocess.TimeoutExpired:rc=124
  return {'command':[str(c) for c in cmd],'returncode':rc,'seconds':round(time.monotonic()-begin,3)}
 for ports in [1,2,4]:
  for vcs in [1,2,4]:
   for fault in [None]+(['quiescent','body_token','route'] if ports==4 and vcs==4 and a.faults else []):
    folder=stage/f'p{ports}_v{vcs}{"_"+fault if fault else ""}';folder.mkdir();actual=files
    if fault:
     old,new={
      'quiescent':('(|reserved)||(|source_busy)||(|o_valid)', '(|reserved)||(|source_busy)'),
      'body_token':('.i_body_token(i_packet_body_token)', '.i_body_token(i_packet_token)'),
      'route':('.i_header_valid(i_packet_header_valid),.i_route_match(route_match)', ".i_header_valid(i_packet_header_valid),.i_route_match({(PORTS*PORTS){1'b1}})")}[fault]
     text=rtl.read_text()
     if text.count(old)!=1:raise ValueError('fault anchor '+fault)
     text=text.replace(old,new)
     altered=folder/rtl.name;altered.write_text(text);actual=[altered if f==rtl else f for f in files]
    cmd={'compile':run(folder,'compile',['iverilog','-g2012','-s','tb',f'-Ptb.P={ports}',f'-Ptb.V={vcs}','-o','sim.vvp',source/'switch_egress_typed_top_tb.sv',*actual])}
    if cmd['compile']['returncode']==0:
     cmd['simulate']=run(folder,'simulate',['vvp','sim.vvp'])
     if not fault:
      top='ualink_switch_top';cmd['g2001']=run(folder,'g2001',['iverilog','-g2001','-s',top,f'-P{top}.PORTS={ports}',f'-P{top}.PACKET_VCS={vcs}',f'-P{top}.BUFFERED_EGRESS_ENABLE=1',f'-P{top}.ROUTE_CONFIG_ENABLE=1','-o','elab.vvp',*actual]);cmd['lint']=run(folder,'lint',['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',top,f'-GPORTS={ports}',f'-GPACKET_VCS={vcs}','-GBUFFERED_EGRESS_ENABLE=1','-GROUTE_CONFIG_ENABLE=1',waiver,*actual]);cmd['yosys']=run(folder,'yosys',['yosys','-Q','-T','-p','read_verilog '+' '.join(map(str,actual))+f'; chparam -set PORTS {ports} -set PACKET_VCS {vcs} -set BUFFERED_EGRESS_ENABLE 1 -set ROUTE_CONFIG_ENABLE 1 {top}; hierarchy -check -top {top}; proc; opt; check -assert; stat; write_json hierarchy.json'])
    log=(folder/'simulate.log').read_text() if (folder/'simulate.log').exists() else ''
    passed=all(c['returncode']==0 for c in cmd.values()) and 'TOP_TYPED_PASS' in log
    if fault:
     expected={'quiescent':['TOP_QUIESCENT','TOP_REPACK_COMMIT'],'body_token':['PIPELINE_UNEXPECTED_ERROR','PIPELINE_BODY_NOT_RESERVED'],'route':['PIPELINE_HEADER_TIMEOUT','PIPELINE_UNEXPECTED_ERROR']}[fault]
     passed=cmd['compile']['returncode']==0 and cmd.get('simulate',{}).get('returncode')==1 and any(marker in log for marker in expected)
    structure={}
    if not fault and (folder/'hierarchy.json').exists():
     modules=json.loads((folder/'hierarchy.json').read_text())['modules'];counts={}
     def visit(name):
      m=modules[name];kind=m.get('attributes',{}).get('hdlname',name).split()[0].lstrip('\\');counts[kind]=counts.get(kind,0)+1
      for cell in m.get('cells',{}).values():
       if cell['type'] in modules:visit(cell['type'])
     visit('ualink_switch_top');latches=sum('latch' in cell['type'].lower() for m in modules.values() for cell in m.get('cells',{}).values());structure={'instances':counts,'latches':latches}
     passed=passed and latches==0 and all(counts.get(k)==v for k,v in {'switch_egress_typed_pipeline':1,'switch_route_lookup':1,'switch_route_table':1,'switch_egress_repack':1,'switch_egress_pipeline':1,'switch_egress_vc_queues':1,'switch_egress_scheduler':1,'switch_credit_reservation':2*vcs,'switch_egress_packet_queue':2*vcs,'upli_receive_fifo':2*vcs*ports}.items())
    results.append({'ports':ports,'vcs':vcs,'fault':fault,'commands':cmd,'structure':structure,'passed':passed});print(ports,vcs,fault,passed,log[-190:],flush=True)
 result={'passed':all(c['passed'] for c in results),'cases':results,'sources_sha256':hashes,'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}};(stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

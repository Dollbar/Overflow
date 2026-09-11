#!/usr/bin/env python3
"""Actual production ordered receive test, preserving compiled-source and trace evidence."""
import argparse,hashlib,json,random,re,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())

def stimulus(ports,width,caps):
 rng=random.Random(0xACC+ports);rows=[]
 def t(**kw):
  d=dict(rstn=1,cc=1,bc=1,want=0,port=0,vc=0,pool=0,data=rng.getrandbits(width),cport=0,ready=0,inject=0);d.update(kw);rows.append(tuple(d.values()))
 def setup():
  for _ in range(3):t(rstn=0,cc=0,bc=0)
  for _ in range(4):t(cc=0,bc=0)
  for _ in range(90):t()
 def drain():
  for k in range(ports*80):t(cport=k%ports,ready=1)
 setup()
 for p in range(ports):
  # Reverse account selection and varying pool VC make current-input metadata bugs visible.
  for repeat in range(max(caps[p*5:p*5+5])+1):
   for a in (4,2,0,3,1):t(want=1,port=p,vc=(repeat+p)%4 if a==4 else a,pool=int(a==4))
 for _ in range(20):t(ready=0,cport=rng.randrange(4))
 drain()
 for p in range(ports):
  for a in range(5):
   if caps[p*5+a]==0:t(port=p,vc=a if a<4 else 3,pool=int(a==4),inject=1)
 if ports<4:t(port=3,vc=1,inject=1)
 for k in range(1700):t(want=1,port=k%ports,vc=(k//ports)%4,pool=int((k//3)%2),cport=(k//3)%ports,ready=int(k%7!=0))
 drain()
 # Pending accepted crosses reset; stale metadata must never enter the new epoch.
 t(want=1,port=0,vc=0,pool=1);t(rstn=0,cc=0,bc=0)
 setup()
 for k in range(350):t(want=1,port=k%ports,vc=(k//ports+1)%4,pool=int(k%3==0),cport=(k+1)%ports,ready=int(k%4!=0))
 drain()
 for _ in range(30):t()
 return rows

def main():
 a=argparse.ArgumentParser(description=__doc__);a.add_argument('--label',required=True);a.add_argument('--kd28-root',type=Path,required=True);a.add_argument('--ports',type=int,choices=(1,2,4));a.add_argument('--expect-missing',action='store_true');a.add_argument('--fault',choices=('live_account','live_port','payload_bit'));args=a.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',args.label):raise ValueError('safe fresh label')
 stage=ROOT/'build/verification/upli_channels/ordered_receive'/args.label;stage.mkdir(parents=True,exist_ok=False);src=stage/'sources';src.mkdir()
 dep=json.loads((ROOT/'third_party/kd28_dependency.json').read_text());inputs={}
 for name,h in dep['functional_sources_sha256'].items():
  p=args.kd28_root/name;b=p.read_bytes()
  if hashlib.sha256(b).hexdigest()!=h:raise ValueError('external source identity '+name)
  inputs[p]=b
 for p in (ROOT/'rtl').rglob('*.v'):inputs[p]=p.read_bytes()
 hashes={};files=[]
 for p,b in inputs.items():
  f=src/p.name
  if f.exists():raise ValueError('basename collision '+p.name)
  hashes[str(p)]=hashlib.sha256(b).hexdigest()
  if args.fault and p.name=='upli_ordered_receive_channel.v':
   old,new={'live_account':('order_memory[reg_write_pointer] <= reg_receive_account;',"order_memory[reg_write_pointer] <= i_receive_pool ? 3'd4 : {1'b0,i_receive_vc};"),'live_port':('(reg_receive_port == C_PORT)','(i_receive_port == C_PORT)'),'payload_bit':('assign o_head_payload = child_head_payload;',"assign o_head_payload = child_head_payload ^ {{(C_PAYLOAD_WIDTH-1){1'b0}},1'b1};")}[args.fault]
   text=b.decode()
   if text.count(old)!=1:raise ValueError('fault anchor')
   b=text.replace(old,new).encode()
  f.write_bytes(b);files.append(str(f))
 for name in ('run_ordered_receive.py','ordered_receive_reference.py','ordered_receive_tb.sv','ordered_receive_mismatch_tb.sv'):(src/name).write_bytes((HERE/name).read_bytes())
 (src/'upli_ordered_receive_channel_execution.md').write_bytes((ROOT/'docs/upli_ordered_receive_channel_execution.md').read_bytes())
 sys.path.insert(0,str(src))
 from ordered_receive_reference import check
 containment_dir=stage/'mismatch_containment';containment_dir.mkdir()
 containment_compile=['iverilog','-g2012','-s','ordered_receive_mismatch_tb','-o',str(containment_dir/'sim.vvp'),str(src/'upli_ordered_receive_channel.v'),str(src/'ordered_receive_mismatch_tb.sv')]
 containment_process=subprocess.run(containment_compile,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120);(containment_dir/'compile.log').write_bytes(containment_process.stdout)
 containment_run=None
 if containment_process.returncode==0:
  containment_run=subprocess.run(['vvp',str(containment_dir/'sim.vvp')],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120);(containment_dir/'run.log').write_bytes(containment_run.stdout)
 containment={'compile_exit':containment_process.returncode,'run_exit':None if containment_run is None else containment_run.returncode,'passed':containment_run is not None and containment_run.returncode==0 and b'ORDER_MISMATCH_CONTAINED' in containment_run.stdout}
 cases=[]
 for ports in ([args.ports] if args.ports else (1,2,4)):
  caps=([2,0,3,1,4] if ports==1 else [1,3,0,2,4,0,2,1,4,3] if ports==2 else [1,3,0,2,4,0,2,1,4,3,2,1,3,0,4,0,0,0,0,0]);width={1:184,2:580,4:619}[ports];ret=1 if ports==1 else 2 if ports==2 else 4
  c=stage/f'p{ports}';c.mkdir();rows=stimulus(ports,width,caps);(c/'stimulus.txt').write_text(''.join(' '.join(f'{x:x}' for x in row)+'\n' for row in rows));capvalue=sum(v<<(4*k) for k,v in enumerate(caps))
  commands=[('compile',['iverilog','-g2012','-s','tb',f'-Ptb.PORTS={ports}',f'-Ptb.WIDTH={width}',f'-Ptb.RETURN_DEPTH={ret}',f"-Ptb.CAPS={ports*20}'h{capvalue:x}",'-o',str(c/'sim.vvp'),*files,str(src/'ordered_receive_tb.sv')])]
  result={'ports':ports,'width':width,'caps':caps,'rows':len(rows),'return_depth':ret}
  cmd=commands[0][1];p=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120);(c/'compile.log').write_bytes(p.stdout);result['compile']={'command':cmd,'exit':p.returncode}
  if args.expect_missing:
   result['expected_missing_red']=p.returncode!=0 and b'Unknown module type: upli_ordered_receive_channel' in p.stdout;result['passed']=result['expected_missing_red']
  elif p.returncode==0:
   cmd=['vvp',str(c/'sim.vvp')];r=subprocess.run(cmd,cwd=c,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120);(c/'run.log').write_bytes(r.stdout);result['run']={'command':cmd,'exit':r.returncode}
   try:result['check']=check(c/'run.log',ports,width,caps);result['passed']=r.returncode==0 and b'ORDERED_RECEIVE_RUN_DONE' in r.stdout
   except (ValueError,IndexError) as e:result['passed']=False;result['error']=str(e)
   if args.fault:result['fault_detected']=r.returncode==0 and 'error' in result;result['passed']=result['fault_detected']
  else:result['passed']=False
  (c/'check.json').write_text(json.dumps(result,indent=2)+'\n');cases.append(result);print(ports,result.get('error'),result['passed'],flush=True)
 summary={'sources_sha256':hashes,'fault':args.fault,'mismatch_containment':containment,'cases':cases,'passed':containment['passed'] and all(c['passed'] for c in cases),'kind':'missing interface RED' if args.expect_missing else 'independent chronological/credit journal'};(stage/'result.json').write_text(json.dumps(summary,indent=2)+'\n');(stage/'manifest.json').write_text(json.dumps({str(p.relative_to(stage)):hashlib.sha256(p.read_bytes()).hexdigest() for p in stage.rglob('*') if p.is_file()},indent=2)+'\n');return 0 if summary['passed'] else 1
if __name__=='__main__':sys.exit(main())

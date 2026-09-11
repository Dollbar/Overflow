#!/usr/bin/env python3
"""Native Read Response TX regression using the actual common parity primitive.
Run: python3 verification/upli_channels/run_read_response_channel.py --label NEW --faults --static
Outputs: build/verification/upli_channels/read_response_channel/NEW with source snapshots, vectors, logs, result and SHA256 hashes.
Next: install the frozen typed leaf separately from response scheduling and RX management.
"""
import argparse,hashlib,itertools,json,random,re,subprocess
from pathlib import Path
from read_response_reference import FIELDS,pack,expected
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--faults',action='store_true');p.add_argument('--static',action='store_true');a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
 stage=ROOT/'build/verification/upli_channels/read_response_channel'/a.label;stage.mkdir(parents=True,exist_ok=False)
 for name in ('run_read_response_channel.py','read_response_reference.py','read_response_channel_tb.sv'):(stage/name).write_bytes((HERE/name).read_bytes())
 for name in ('upli_read_response_channel.v','upli_parity.v'):(stage/name).write_bytes((ROOT/'rtl/upli'/name).read_bytes())
 rows=[];groups={}
 def add(group,r,v,d,want=None):
  rows.append((r,v,pack(d),*(expected(r,v,d) if want is None else want)));groups[group]=groups.get(group,0)+1
 ones={n:(1<<w)-1 for n,w in FIELDS};zeros={n:0 for n,w in FIELDS}
 add('literal_all_ones',1,1,ones,(1,(1<<624)-1,1,0,0,0));add('literal_reset',0,1,ones,(0,0,0,0,0,0));add('literal_idle',1,0,ones,(0,0,0,0,0,0));add('literal_zero_valid',1,1,zeros,(1,0,1,0,0,0))
 for name,width in FIELDS:
  for bit in range(width):
   d=dict(zeros);d[name]=1<<bit
   for rstn,valid in ((1,1),(1,0),(0,1)):add('every_field_bit',rstn,valid,d)
 for bit in range(512):
  for poison in (0,1):
   d=dict(zeros,data=1<<bit,data_error=poison);add('every_data_bit_with_poison',1,1,d)
 for status,kind,offset,num,last,poison in itertools.product(range(16),range(4),range(4),range(4),range(2),range(2)):
  d=dict(zeros,status=status,type_info=kind,offset=offset,num_beats=num,last=last,data_error=poison,data=0x8000000000000001|(1<<511)|(1<<255),auth_tag=(1<<63)|0x5a,src=0x301,dst=0x2ab,tag=0x777,vc=3,port=2,pool=1)
  add('control_cross_product',1,1,d)
 rng=random.Random(629)
 for _ in range(400):add('random_full_words',rng.randrange(2),rng.randrange(2),{n:rng.getrandbits(w) for n,w in FIELDS})
 (stage/'vectors.txt').write_text(''.join(' '.join(format(x,'x') for x in row)+'\n' for row in rows))
 faults={
 'tag_high':('i_tag & {11{o_valid}}',"(i_tag & 11'h3ff) & {11{o_valid}}"),
 'auth_high':('i_auth_tag & {64{o_valid}}',"(i_auth_tag & 64'h7fffffffffffffff) & {64{o_valid}}"),
 'data_error_lost':('i_data_error & {1{o_valid}}',"1'b0 & {1{o_valid}}"),
 'poison_parity_mask':('.i_data(o_data)', '.i_data(o_data & {512{!o_data_error}})'),
 'status_parity_mask':('.i_data(o_data)',".i_data(o_data & {512{o_status==4'd0}})"),
 'src_control_omitted':('o_vc,o_src,o_dst',"o_vc,10'd0,o_dst"),
 'data_parity_lane_swap':('assign o_data_parity = parity[11:4];','assign o_data_parity = {parity[4],parity[11:5]};'),
 'valid_parity':('assign o_valid_parity = parity[0];','assign o_valid_parity = ~parity[0];'),
 }
 cases=[]
 for fault in [None,*list(faults if a.faults else {})]:
  folder=stage/(fault or 'normal');folder.mkdir();s=(stage/'upli_read_response_channel.v').read_text()
  if fault:
   old,new=faults[fault]
   if s.count(old)!=1:raise ValueError(fault+' anchor absent/ambiguous')
   s=s.replace(old,new)
  (folder/'upli_read_response_channel.v').write_text(s);(folder/'vectors.txt').write_bytes((stage/'vectors.txt').read_bytes());item={'fault':fault}
  for phase,cmd in [('compile',['iverilog','-g2012','-s','tb','-o','sim.vvp','upli_read_response_channel.v','../upli_parity.v','../read_response_channel_tb.sv']),('run',['vvp','sim.vvp'])]:
   with (folder/(phase+'.log')).open('w') as log:
    try:code=subprocess.run(cmd,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=45).returncode
    except subprocess.TimeoutExpired:code=124
   item[phase]={'command':cmd,'exit':code}
   if phase=='compile' and code:break
  log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
  item['passed']=item['compile']['exit']==0 and item.get('run',{}).get('exit')==(1 if fault else 0) and ('READ_RESPONSE_MISMATCH' if fault else 'READ_RESPONSE_PASS') in log;cases.append(item);print(fault or 'normal',item['passed'],log.splitlines()[0] if log else '',flush=True)
 static=[]
 if a.static:
  (stage/'check.ys').write_text('read_verilog upli_read_response_channel.v upli_parity.v\nhierarchy -check -top upli_read_response_channel\nproc\nopt\ncheck -assert\nstat\n')
  for name,cmd in [('g2001',['iverilog','-g2001','-s','upli_read_response_channel','-o','compile.vvp','upli_read_response_channel.v','upli_parity.v']),('lint',['verilator','--lint-only','-Wall','--top-module','upli_read_response_channel','upli_read_response_channel.v','upli_parity.v']),('yosys',['yosys','-Q','-T','-s','check.ys'])]:
   with (stage/(name+'.log')).open('w') as log:
    try:code=subprocess.run(cmd,cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=45).returncode
    except subprocess.TimeoutExpired:code=124
   static.append({'tool':name,'exit':code,'command':cmd})
 result={'passed':all(c['passed'] for c in cases) and all(s['exit']==0 for s in static),'normal_vectors':len(rows),'groups':groups,'cases':cases,'static':static,'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}}
 (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

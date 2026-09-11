"""Exercise complete Read requests and both ReadResponse modes through actual receiver RTL.
Run: python3 verification/endpoint_transaction/run_read_receiver.py --label NEW [--baseline]
Outputs snapshots and result.json beneath build/verification/endpoint_transaction/NEW.
Next validate per-Tag bitmap correlation and actual endpoint memory causality separately.
"""
from pathlib import Path
import argparse,hashlib,json,re
import run_write_receiver as base
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
def vectors():
 records=[];requests=[];responses=[]
 def rec(low=0,high=0,lc=0,hc=3):records.append(low|(high<<256)|(lc<<514)|(hc<<517))
 for off in range(64):
  for length in range(64-off):
   tag=len(requests)%2048;q=base.request(tag,(1<<56)+off*4,length,read=True)
   q.update(attr=(tag*37)&255,asi=tag%4,meta=(tag*19)&255)
   rec(base.control(q)<<(128*(tag%2)))
   requests.append(base.pack([(0,1),(0,1),(tag,11),(513,10),(17,10),(q['address'],57),(length,6),(q['attr'],8),(0,2),(0,1),(q['asi'],2),(q['meta'],8),(0,2048),(0,256)]))
 tag=0
 for count in range(1,5):
  for status in (0,2,3,6,8):
   for offset in range(4):
    for last in range(2):
     raw=(2<<60)|(tag<<47)|((count-1)<<44)|(offset<<42)|(status<<38)|(1<<37)|(last<<36)|(513<<26)|(17<<16)
     rec(raw<<(64*(tag%4)))
     for beat in range(count):
      data=int.from_bytes(bytes((tag*17+beat*71+b*5)&255 for b in range(64)),'little')
      rec(data&((1<<256)-1),data>>256,1,1)
      responses.append(base.pack([(0,1),(0,2),(tag,11),(17,10),(status,4),(offset if count==1 else beat,2),(last if count==1 else beat==count-1,1),(count-1,2),(data,512),(0,1)]))
     tag+=1
 # Old WriteFull owner tail sharing a Control with a four-Beat ReadResponse.
 q=base.request(2001,128,15,full=True);data=(1<<511)|0xdeadbeef;be=((1<<64)-1)<<128
 requests.append(base.pack([(1,1),(1,1),(2001,11),(513,10),(17,10),(128,57),(15,6),(q['attr'],8),(0,2),(0,1),(q['asi'],2),(q['meta'],8),(data,2048),(be,256)]))
 rec(base.control(q),data&((1<<256)-1),0,1)
 rec((2<<60)|(2002<<47)|(3<<44)|(3<<42)|(1<<37)|(513<<26)|(17<<16),data>>256,0,1)
 for beat in range(4):
  value=(beat+1)|((beat+19)<<256);rec(value&((1<<256)-1),value>>256,1,1)
  responses.append(base.pack([(0,1),(0,2),(2002,11),(17,10),(0,4),(beat,2),(beat==3,1),(3,2),(value,512),(0,1)]))
 return records,requests,responses

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--baseline',action='store_true');p.add_argument('--faults',action='store_true');a=p.parse_args()
 if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('fresh safe label required')
 stage=ROOT/'build/verification/endpoint_transaction'/a.label;stage.mkdir(parents=True,exist_ok=False)
 if not a.baseline:base.TB=base.TB.replace('.WRITE_ENABLE(1)', '.WRITE_ENABLE(1),.FULL_READ_ENABLE(1)')
 vals=vectors();results=[]
 for name,kwargs in [('ordered',{}),('backpressure',{'long_stall':True})]:
  result=base.run_case(stage/name,vals,**kwargs)
  if a.baseline:result['expected_red']=result.get('compile_exit')==0 and result.get('run_exit')==1 and 'WRITE_RX_ERROR' in (stage/name/'run.log').read_text()
  results.append({'name':name,'passed':result.get('expected_red') if a.baseline else result['passed']})
  if a.baseline:break
 if not a.baseline:
  q=base.request(13,252,1,read=True)
  negatives={'request_cross_region':base.control(q),'request_numbeats':base.control(base.request(13,0,0,read=True))|1,'read_reserved_status':(2<<60)|(1<<37)|(1<<38),'read_rsp_type':(2<<60)|(1<<37)|(1<<14),'write_response_data':(2<<60)|(1<<44)}
  for name,word in negatives.items():
   result=base.run_case(stage/name,([word|(3<<517)],[],[]),expect_error=True)
   results.append({'name':name,'passed':result['passed']})
  if a.faults:
   faults={
    'burst_truncated':("({2'd0,data_response_length}+4'd1)<<1","4'd2"),
    'burst_offset_zero':("?response_beat:rsp_out[43:42]","?2'd0:rsp_out[43:42]"),
    'early_last':("?(response_beat==rsp_out[45:44]):rsp_out[36]","?1'b1:rsp_out[36]")}
   for name,fault in faults.items():
    result=base.run_case(stage/name,vals,fault=fault)
    results.append({'name':name,'passed':result['expected_red']})
 (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
 report={'passed':all(x['passed'] for x in results),'baseline':a.baseline,'cases':results,'requests':len(vals[1]),'responses':len(vals[2]),'records':len(vals[0]),'runner_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
 report['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
 (stage/'result.json').write_text(json.dumps(report,indent=2)+'\n');print(report['passed'],report['requests'],report['responses']);return 0 if report['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

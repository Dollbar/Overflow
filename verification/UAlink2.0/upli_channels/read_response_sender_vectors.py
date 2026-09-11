"""Deterministic semantic-event stimulus, independent of DUT wiring and state."""
import random
from read_response_sender_reference import Journal,pack,unpack

def generate(ports,width=4):
 rng=random.Random(0x619+ports);m=Journal(ports,width);rows=[];coverage={};returned=[[] for _ in range(ports)];seq=0
 def tick(label='idle',auto=True,**kw):
  i=dict(rstn=1,cc=1,bc=1,cv=0,port=0,vc=0,pools=0,payload=rng.getrandbits(2476),rv=0,rpool=0,rvc=0,rnum=0,done=0)
  if auto:
   for p,q in enumerate(returned):
    if q:
     vc,pool=q.pop(0);i['rv']|=1<<p;i['rpool']|=pool<<p;i['rvc']|=vc<<(2*p)
  i.update(kw);o=m.inspect(i);rows.append(tuple(i.values())+o);m.step(i,o)
  if not i['rstn']:
   for q in returned:q.clear()
  elif o[1]:returned[o[2]].append((o[3],o[4]))
  coverage[label]=coverage.get(label,0)+1
  return o
 def init():
  tick('reset',auto=False,rstn=0);tick('reset',auto=False,rstn=0)
  tick('unconnected',cc=0,bc=0,cv=1,payload=0)
  tick('no_credit',cv=1,payload=0)
  mask=(1<<ports)-1
  for a in range(5):tick('initial_credit',auto=False,rv=mask,rpool=mask if a==4 else 0,rvc=sum((a%4)<<(2*p) for p in range(ports)),rnum=sum(3<<(2*p) for p in range(ports)))
  tick('init_before_confirm',auto=False,done=mask,cv=1,payload=0)
  tick('init_same_edge_no_bypass',auto=False,done=mask,cv=1,payload=0)
  tick('initialized')
 def payload(n,status=0,offset=0,last=1):
  nonlocal seq
  seq+=1;words=[]
  for k in range(4):
   d=dict(auth=rng.getrandbits(64),src=(1023-k*127-seq)%1024,dst=(1023-seq)%1024,tag=(2047-seq)%2048,num=n-1,data=rng.getrandbits(512),status=status,offset=k if n>1 else offset,last=int(k==n-1) if n>1 else last,error=(seq+k)%2,kind=seq%4)
   words.append(pack(d))
  return sum(w<<(619*k) for k,w in enumerate(words))
 def submit(label,port,vc,pools,word,auto=True):
  for _ in range(40):
   o=tick(label,auto=auto,cv=1,port=port,vc=vc,pools=pools,payload=word)
   if o[0]:return o
  raise RuntimeError(('reference blocked',label,port,m.balance,m.queue))
 def drain():
  for _ in range(ports*4+3):tick('tail_noise')
 init()
 # Complete bits' local codec has separately specified absolute physical locations.
 bitpos={'auth':555,'src':545,'dst':535,'tag':524,'num':522,'data':10,'status':6,'offset':4,'last':3,'error':2,'kind':0}
 for name,start in bitpos.items():
  d={k:0 for k in bitpos};d[name]=1
  if pack(d)!=1<<start or unpack(1<<start)!=d:raise RuntimeError('independent codec location '+name)
 for p in range(ports):
  for n in range(1,5):
   for pools in range(1<<n):
    for status in (0,2,3,6,8):
     submit('complete_geometry',p,(p+n+pools)%4,pools,payload(n,status,offset=pools%4,last=pools%2));drain()
 # Multiple ports own saved tails simultaneously; candidate changes after first beat.
 for turn in range(4):
  for p in range(ports):submit('concurrent_ports',p,turn,(p+turn)%16,payload(4,8))
  drain()
 # Independent single beats retain arbitrary offset and Last, including nonterminal.
 for offset in range(4):
  for last in range(2):submit('single_transparent',ports-1,3,1,payload(1,3,offset,last));drain()
 # Field-level malformed multi inputs never debit; Src variation above remains legal.
 for name in ('num','tag','dst','kind','status','offset','last'):
  w=payload(4);d=unpack((w>>619)&((1<<619)-1));d[name]^=1;w=(w&~(((1<<619)-1)<<619))|(pack(d)<<619)
  for _ in range(ports+1):
   o=tick('bad_'+name,cv=1,port=0,payload=w)
   if not o[7] or o[0]:raise RuntimeError('bad geometry oracle')
 if ports<4:
  o=tick('unused_port',cv=1,port=3,payload=payload(1))
  if not o[7]:raise RuntimeError('bad port oracle')
 # RequiredN minus one prior credit, and same-edge return cannot bypass reservation.
 for n in (2,3,4):
  init();w=payload(1)
  for _ in range(5-n):submit('deplete',0,2,0,w,auto=False)
  staged=payload(n,6)
  for _ in range(ports+2):
   o=tick('one_credit_short',auto=False,cv=1,port=0,vc=2,payload=staged)
   if o[0]:raise RuntimeError('shortage admitted')
  returned[0].pop(0)
  o=tick('return_no_bypass',auto=False,cv=1,port=0,vc=2,payload=staged,rv=1,rvc=2)
  if o[0]:raise RuntimeError('same-edge bypass')
  submit('after_return',0,2,0,staged,auto=False)
  for _ in range(ports*4+2):tick('reserved_tail_no_returns',auto=False)
 # Reset cancels a partially transmitted response before its next local slot.
 init();submit('reset_owned_first',0,1,5,payload(4,2));tick('reset_owned',auto=False,rstn=0);tick('reset_clean',auto=False)
 init();submit('post_reset',ports-1,3,15,payload(4,8));drain()
 # Invalid bank event is diagnosed and sticky-blocks subsequent valid candidates.
 tick('overflow',auto=False,rv=1,rnum=3)
 for _ in range(ports+3):tick('sticky_block',auto=False,cv=1,port=0,payload=payload(1))
 tick('final_reset',auto=False,rstn=0);tick('final_clean',auto=False)
 return rows,coverage

if __name__=='__main__':
 import sys,json
 from pathlib import Path
 p=int(sys.argv[1]);w=int(sys.argv[2]);out=Path(sys.argv[3]);rows,c=generate(p,w)
 out.write_text(''.join(' '.join(format(x,'x') for x in row)+'\n' for row in rows));print(json.dumps({'rows':len(rows),'coverage':c}))

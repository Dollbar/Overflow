"""Independent per-egress deque service model; no RTL state access."""
from collections import deque
import random

class Scheduler:
 def __init__(self,p,v,d,t,limit):
  self.p,self.v,self.d,self.t,self.limit=p,v,d,t,limit;self.reset()
 def reset(self):
  self.owner=[None]*self.p;self.order=[[deque(range(self.v)),deque(range(self.v))] for _ in range(self.p)];self.runs=[0]*self.p
 def step(self,rst,valid,data,last,token,ready):
  if not rst:self.reset();return [0]*9
  out=[0]*9
  for e in range(self.p):
   owned=self.owner[e];choice=owned
   if choice is None:
    heads=[next((vc for vc in self.order[e][kind] if valid>>((kind*self.v+vc)*self.p+e)&1),None) for kind in (0,1)]
    kind=1 if heads[1] is not None and (heads[0] is None or self.runs[e]<self.limit) else 0
    if heads[kind] is not None:choice=(kind,heads[kind])
   if owned is not None:out[8]|=1<<e
   if choice is None:continue
   kind,vc=choice;s=(kind*self.v+vc)*self.p+e
   out[7]|=1<<s
   if ready>>e&1:out[0]|=1<<s
   if not (valid>>s&1):continue
   out[1]|=1<<e;out[2]|=((data>>(s*self.d))&((1<<self.d)-1))<<(e*self.d);out[3]|=((last>>s)&1)<<e
   out[4]|=((token>>(s*self.t))&((1<<self.t)-1))<<(e*self.t);out[5]|=vc<<(e*2);out[6]|=kind<<e
   if ready>>e&1 and last>>s&1:
    self.owner[e]=None;q=self.order[e][kind]
    while q[0]!=vc:q.rotate(-1)
    q.rotate(-1);self.runs[e]=min(self.limit,self.runs[e]+1) if kind else 0
   else:self.owner[e]=choice
  return out

def vectors(path,p,v,d,t,limit):
 rng=random.Random(1203+p*97+v);model=Scheduler(p,v,d,t,limit);rows=[];coverage={'cycles':0,'last':0,'stalls':0,'bubbles':0,'reset_owned':0,'served':[0]*(2*v*p)}
 def emit(rst,valid,data,last,token,ready):
  if not rst and any(x is not None for x in model.owner):coverage['reset_owned']+=1
  expected=model.step(rst,valid,data,last,token,ready);rows.append([rst,valid,data,last,token,ready,*expected]);coverage['cycles']+=1
  for e in range(p):
   if expected[1]>>e&1:
    if ready>>e&1:
     if expected[3]>>e&1:
      coverage['last']+=1;s=next(s for s in range(2*v*p) if s%p==e and expected[7]>>s&1);coverage['served'][s]+=1
    else:coverage['stalls']+=1
   elif expected[8]>>e&1:coverage['bubbles']+=1
  return expected
 n=2*v*p;full=(1<<n)-1;physical=(1<<p)-1
 emit(0,full,0,full,0,physical)
 # Literal class service schedule independent of model's choice computation.
 for k in range((limit+1)*v*3):
  words=sum(((0x9283+s*0x713+k)&((1<<d)-1))<<(s*d) for s in range(n));tok=sum((s&((1<<t)-1))<<(s*t) for s in range(n));r=emit(1,full,words,full,tok,physical)
  phase=k%(limit+1);expected_class=0 if phase==limit else 1;vc=(k//(limit+1))%v if expected_class==0 else (k-k//(limit+1))%v
  for e in range(p):
   if not(r[7]>>((expected_class*v+vc)*p+e)&1):raise ValueError('literal service schedule disagrees')
 # Stalled first request then arriving higher priority response; body bubbles.
 emit(0,0,0,0,0,0)
 req=sum(1<<e for e in range(p));rsp=sum(1<<(v*p+e) for e in range(p))
 emit(1,req,0x123456,0,0,0);emit(1,req|rsp,0x123456,0,0,0)
 emit(1,rsp,0,full,0,physical);emit(1,req|rsp,0x123456,req,0,physical)
 emit(1,rsp,0,0,0,0);emit(0,full,0,full,0,physical)
 # Random legal queued packet streams: stalled beats remain stable, owned bubbles allowed.
 packets=[None]*n;positions=[0]*n;held=[False]*n;serial=0
 for cycle in range(2000):
  if cycle in (719,1421):
   emit(0,full,0,full,0,physical);packets=[None]*n;positions=[0]*n;held=[False]*n;continue
  valid=data=last=token=0
  for s in range(n):
   if packets[s] is None and rng.randrange(5)!=0:
    serial+=1;packets[s]=([rng.getrandbits(d) for _ in range(1+rng.randrange(5))],serial&((1<<t)-1));positions[s]=0
   if packets[s] is None:continue
   words,tag=packets[s];pos=positions[s];active=held[s] or rng.randrange(4)!=0
   data|=words[pos]<<(s*d);token|=tag<<(s*t)
   if active:valid|=1<<s
   if pos==len(words)-1 or not active and rng.randrange(2):last|=1<<s
  ready=rng.getrandbits(p);r=emit(1,valid,data,last,token,ready)
  for s in range(n):
   held[s]=bool(valid>>s&1 and not (r[0]>>s&1))
   if valid>>s&1 and r[0]>>s&1:
    positions[s]+=1
    if positions[s]==len(packets[s][0]):packets[s]=None
 emit(0,0,0,0,0,0)
 if not all(coverage['served']) or not all(coverage[k] for k in ('stalls','bubbles','reset_owned')):raise ValueError('missing directed coverage')
 path.write_text(''.join(' '.join(format(x,'x') for x in row)+'\n' for row in rows));return coverage

"""Integer resource accounting + rotating deque priority, independent of RTL implementation."""
from collections import deque
class Model:
 def __init__(self,caps):self.caps=caps;self.p=len(caps);self.reset()
 def reset(self):self.free=self.caps[:];self.order=[deque(range(self.p)) for _ in self.caps]
 def observe(self,x,w):
  valid,routes,units,ready,rv,ru,rst=x
  need=[units>>(i*w)&((1<<w)-1) for i in range(self.p)];ret=[ru>>(i*w)&((1<<w)-1) for i in range(self.p)];dest=[];err=relerr=grant=src_ready=gu=ra=0
  for s in range(self.p):
   matches=[e for e in range(self.p) if routes>>(s*self.p+e)&1]
   d=matches[0] if len(matches)==1 else None;dest.append(d)
   if valid>>s&1 and (d is None or not 1<=need[s]<=self.caps[d]):err|=1<<s
  for e in range(self.p):
   if rv>>e&1 and not 1<=ret[e]<=self.caps[e]-self.free[e]:relerr|=1<<e
   if rst and not(relerr>>e&1):
    if rv>>e&1:ra|=1<<e
    candidates=[s for s in self.order[e] if valid>>s&1 and not(err>>s&1) and dest[s]==e and need[s]<=self.free[e]]
    if ready>>e&1 and candidates:
     s=candidates[0];grant|=1<<(e*self.p+s);src_ready|=1<<s;gu|=need[s]<<(e*w)
  flat=lambda a:sum(v<<(e*w) for e,v in enumerate(a))
  return (src_ready,grant,gu,ra,flat(self.free),flat([c-f for c,f in zip(self.caps,self.free)]),err if rst else 0,relerr if rst else 0,int(bool(rst and (err or relerr))))
 def step(self,x,y,w):
  if not x[-1]:self.reset();return
  _,grant,gu,ra,*_=y
  for e in range(self.p):
   if ra>>e&1:self.free[e]+=(x[5]>>(e*w))&((1<<w)-1)
   winners=[s for s in range(self.p) if grant>>(e*self.p+s)&1]
   if winners:
    self.free[e]-=(gu>>(e*w))&((1<<w)-1);s=winners[0]
    while self.order[e][0]!=s:self.order[e].rotate(-1)
    self.order[e].rotate(-1)

def vectors(ports,w,caps):
 import random
 r=random.Random(0xCA9+ports);m=Model(caps);rows=[];coverage={}
 def tick(label,v=0,rt=0,u=0,ready=None,rv=0,ru=0,rst=1):
  x=(v,rt,u,(1<<ports)-1 if ready is None else ready,rv,ru,rst);y=m.observe(x,w);rows.append(x+y);m.step(x,y,w);coverage[label]=coverage.get(label,0)+1;return y
 def all_to(e):return sum(1<<(s*ports+e) for s in range(ports))
 ones=sum(1<<(s*w) for s in range(ports));mask=(1<<ports)-1
 tick('reset',rst=0);tick('idle')
 # Saturated contenders: release previous grant on the next cycle, enough initial capacity.
 for e in range(ports):
  if caps[e]<2:continue
  tick('fair_reset',rst=0);last=0;seen=[]
  for k in range(ports*8):
   y=tick('fairness',mask,all_to(e),ones,rv=(1<<e) if last else 0,ru=(1<<(e*w)) if last else 0)
   g=(y[1]>>(e*ports))&mask;seen.append(g);last=bool(g)
  expected=[1<<(k%ports) for k in range(ports*8)]
  if seen!=expected:raise ValueError('independent fairness sequence')
  for k in range(4):tick('backpressure',mask,all_to(e),ones,ready=0)
 # Whole packet consumes all capacity; release cannot bypass same-edge eligibility.
 for e in range(ports):
  if not caps[e]:continue
  tick('reset_capacity',rst=0);rt=all_to(e);u=caps[e]
  tick('whole_packet',1,rt,u)
  tick('full_backpressure',1,rt,1)
  tick('release_no_bypass',1,rt,1,rv=1<<e,ru=caps[e]<<(e*w))
  tick('after_release',1,rt,1)
  tick('invalid_release',1,rt,1,rv=1<<e,ru=caps[e]<<(e*w))
 # Parallel distinct egress, resets with nonempty reservation, malformed sources.
 tick('reset_parallel',rst=0);route=sum(1<<(s*ports+s) for s in range(ports));tick('parallel',mask,route,ones)
 tick('zero_units',mask,route,0);tick('no_route',mask,0,ones)
 if ports>1:tick('multiroute',mask,all_to(0)|all_to(1),ones)
 tick('reset_outstanding',rst=0)
 for k in range(900):
  routes=0;units=0
  for s in range(ports):
   d=r.randrange(ports);routes|=(1<<d)<<(s*ports);units|=r.randrange(1,min((1<<w)-1,max(caps)+1)+1)<<(s*w)
  rv=ru=0
  for e in range(ports):
   used=caps[e]-m.free[e]
   if used and r.randrange(3)==0:rv|=1<<e;ru|=r.randrange(1,used+1)<<(e*w)
  tick('random',r.randrange(1<<ports),routes,units,r.randrange(1<<ports),rv,ru,rst=int(k%137!=0))
 tick('final_reset',rst=0);tick('final_idle')
 return rows,coverage

"""Independent staged RdRsp event/credit journal, with no RTL imports."""
from collections import Counter
FIELDS=(('auth',64),('src',10),('dst',10),('tag',11),('num',2),('data',512),('status',4),('offset',2),('last',1),('error',1),('kind',2))
def pack(d):
 w=0
 for name,n in FIELDS:
  if not 0<=d[name]<(1<<n):raise ValueError(name)
  w=w*(1<<n)+d[name]
 return w

def unpack(w):
 d={}
 for name,n in reversed(FIELDS):d[name]=w% (1<<n);w//=1<<n
 return d

def parity(w,port,vc,pool,valid):
 if not valid:return 0
 d=unpack(w);auth=d['auth'].bit_count()%2
 control=(sum(d[n].bit_count() for n in ('src','dst','tag','num','status','offset','last','error','kind'))+port.bit_count()+vc.bit_count()+pool)%2
 dp=sum((((d['data']>>(64*k))&((1<<64)-1)).bit_count()%2)<<k for k in range(8))
 return 1|(control<<1)|(auth<<2)|(dp<<3)

class Journal:
 def __init__(self,ports,width=4,capacity=4,init_cycles=2):
  self.p=ports;self.width=width;self.capacity=capacity;self.init_cycles=init_cycles;self.reset()
 def reset(self):
  self.balance=[0]*(self.p*5);self.initial=[0]*self.p;self.confirmed=[False]*self.p;self.queue=[[] for _ in range(self.p)];self.phase=None;self.bank_error=False;self.sticky=False
 def inspect(self,i):
  words=[(i['payload']>>(619*k))&((1<<619)-1) for k in range(4)];first=unpack(words[0]);n=first['num']+1
  good=0<=i['port']<self.p
  if n>1:
   for k,w in enumerate(words[:n]):
    b=unpack(w)
    good &= all(b[x]==first[x] for x in ('num','tag','dst','kind','status')) and b['offset']==k and b['last']==int(k==n-1)
  bad=bool(i['rstn'] and i['cv'] and not good)
  active=bool(i['rstn'] and i['cc'] and i['bc'] and not self.bank_error and not self.sticky)
  accepted=False;word=port=vc=pool=0;valid=False
  if active and self.phase is not None and self.queue[self.phase]:
   word,vc,pool=self.queue[self.phase][0];port=self.phase;valid=True
  elif active and i['cv'] and good and (self.phase is None or self.phase==i['port']) and not self.queue[i['port']] and self.confirmed[i['port']]:
   needs=Counter(4 if i['pools']>>k&1 else i['vc'] for k in range(n))
   if all(self.balance[i['port']*5+a]>=count for a,count in needs.items()):
    accepted=True;valid=True;word=words[0];port=i['port'];vc=i['vc'];pool=i['pools']&1
  balances=sum(b<<(a*self.width) for a,b in enumerate(self.balance));confirmed=sum(int(v)<<p for p,v in enumerate(self.confirmed));busy=sum(bool(q)<<p for p,q in enumerate(self.queue))
  return (int(accepted),int(valid),port,vc,pool,word,parity(word,port,vc,pool,valid),int(bad),int(self.bank_error),int(self.sticky or self.bank_error),balances,confirmed,busy,int(self.phase is not None),self.phase or 0)
 def step(self,i,o):
  if not i['rstn']:self.reset();return
  accepted,valid,port,vc,pool,word=o[:6];old_error=self.bank_error;new=self.balance[:];bad=False
  if valid:
   acc=port*5+(4 if pool else vc)
   if not i['bc'] or not self.confirmed[port] or self.balance[acc]<1:bad=True
   new[acc]-=1
  for p in range(4):
   if p>=self.p:
    bad |= bool((i['rv']|i['done'])>>p&1);continue
   if (i['rv']>>p&1) or (not self.confirmed[p] and (i['done']>>p&1)):bad |= not i['cc']
   if i['rv']>>p&1:
    acc=p*5+(4 if i['rpool']>>p&1 else (i['rvc']>>(2*p))&3);new[acc]+=((i['rnum']>>(2*p))&3)+1
  bad |= any(not 0<=b<=self.capacity for b in new)
  if not bad:
   self.balance=new
   for p in range(self.p):
    if not self.confirmed[p]:
     self.initial[p]=self.initial[p]+1 if i['done']>>p&1 else 0
     self.confirmed[p]=self.initial[p]>=self.init_cycles
  self.bank_error=bool(bad);self.sticky|=old_error
  if accepted:
   n=unpack(word)['num']+1
   self.queue[port]=[((i['payload']>>(619*k))&((1<<619)-1),vc,(i['pools']>>k)&1) for k in range(1,n)]
  elif valid:self.queue[port].pop(0)
  if self.phase is not None:self.phase=(self.phase+1)%self.p
  elif accepted:self.phase=(port+1)%self.p

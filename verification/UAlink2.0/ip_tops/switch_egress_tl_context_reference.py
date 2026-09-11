"""Elastic full-record oracle using the existing independent Python TL context model.
The stimulus's field literals and expected class sentinels are separate from the RTL.
"""
from copy import deepcopy
import random
from receive_context import ReceiveContext
CLASSES={'CONTROL':0,'DATA':1,'BYTE_ENABLE':2,'NOP':3,'MESSAGE':4,'POISON':5,'AUTH':6}
WIDTHS=[1,1,544,None,2,1,1,6,7,73,584,80,80,1,1,1,1,1]
def packed(values,width):return sum(x<<(width*i) for i,x in enumerate(values))
def proposal(context,record):
 msg=(record>>512)&3;types=(record&255,(record>>256)&255)
 return context.step(record&((1<<256)-1),msg=tuple(types[i] if msg>>i&1 else None for i in range(2)),transfer=False)
def before(context):
 q=context.pending
 return len(q),sum((x.kind=='B')<<i for i,x in enumerate(q)),sum((x.slot|(int(x.reserve)<<5)|(int(x.release_data)<<6)|(int(x.release_cmd)<<7))<<(8*i) for i,x in enumerate(q))
def accept(context,record):
 msg=(record>>512)&3;return context.step(record&((1<<256)-1),msg=tuple(((record>>(256*i))&255) if msg>>i&1 else None for i in range(2)))
class Oracle:
 def __init__(self,p,v,t):self.p=p;self.v=v;self.t=t;self.reset(0)
 def reset(self,auth):self.context=[ReceiveContext(bool(auth>>e&1)) for e in range(self.p)];self.held=[None]*self.p;self.error=[False]*self.p
 def step(self,rst,auth,valid,record,token,vc,response,last,ready):
  result=[0]*18
  if not rst:self.reset(auth);return result
  for e in range(self.p):
   rec=(record>>(e*544))&((1<<544)-1);tag=(token>>(e*self.t))&((1<<self.t)-1);v=(vc>>(e*2))&3;old=self.held[e];iv=valid>>e&1;outready=ready>>e&1
   try:prop=proposal(self.context[e],rec);legal=v<self.v
   except ValueError:prop=None;legal=False
   err=bool(iv and not legal and not self.error[e]);can=not self.error[e] and (old is None or outready) and (not iv or legal)
   result[0]|=int(can)<<e;result[14]|=int(err)<<e;result[15]|=int(self.error[e])<<e
   if old is not None:
    result[1]|=1<<e
    for i,(value,width) in enumerate(zip(old,[544,self.t,2,1,1,6,7,73,584,80,80,1]),2):result[i]|=value<<(e*width)
    if outready:result[17]|=1<<e;self.held[e]=None
   if iv and can:
    result[16]|=1<<e;pending,be,meta=before(self.context[e]);classes=CLASSES[prop['classes'][0]]|(CLASSES[prop['classes'][1]]<<3)
    self.held[e]=(rec,tag,v,(response>>e)&1,(last>>e)&1,classes,pending,be,meta,packed(prop['demands'],4),packed(prop['releases'],4),int(prop['store']));accept(self.context[e],rec)
   self.error[e]|=err
  return result

def vectors(path,p,v,t):
 rng=random.Random(5139+p*11+v);m=Oracle(p,v,t);rows=[];cov={'cycles':0,'captures':0,'retired':0,'errors':0,'stalls':0,'resets_held':0,'classes':[0]*7,'ports_errors':[0]*p}
 def emit(rst,auth,valid,rec,tag,vc,resp,last,ready):
  if not rst:cov['resets_held']+=sum(x is not None for x in m.held)
  out=m.step(rst,auth,valid,rec,tag,vc,resp,last,ready);shift=0;bus=0
  for x,w in zip(out,[t if w is None else w for w in WIDTHS]):bus|=x<<shift;shift+=p*w
  rows.append([rst,auth,valid,rec,tag,vc,resp,last,ready,bus]);cov['cycles']+=1;cov['captures']+=out[16].bit_count();cov['retired']+=out[17].bit_count();cov['errors']+=out[14].bit_count();cov['stalls']+=(out[1]&~ready).bit_count()
  for e in range(p):
   if out[14]>>e&1:cov['ports_errors'][e]+=1
   if out[17]>>e&1:
    cl=(out[7]>>(e*6))&63;cov['classes'][cl&7]+=1;cov['classes'][cl>>3]+=1
  return out
 def frame(lower=0,upper=None,msg=(None,None)):
  upper=rng.getrandbits(256) if upper is None else upper;record=lower|(upper<<256);bits=0
  for i,kind in enumerate(msg):
   if kind is not None:record=(record&~(255<<(i*256)))|(kind<<(i*256));bits|=1<<i
  return record|(bits<<512)|(rng.getrandbits(30)<<514)
 for authbit in (0,1):
  auth=((1<<p)-1) if authbit else 0;emit(0,auth,0,0,0,0,0,0,0)
  programs=[]
  for e in range(p):
   c=ReceiveContext(bool(authbit));fs=[];read=(1<<124)|(3<<118)|((e%4)<<116)|(1<<102)
   def add(rec,expected=None):
    r=accept(c,rec)
    if expected is not None and r['classes']!=expected:raise ValueError('literal class sentinel')
    fs.append(rec)
   for repeat in range(5):
    add(frame(read),('CONTROL','AUTH' if authbit else 'NOP'))
    # One compact Write with actual ordered Data/Data/BE tenure.
    add(frame((3<<60)|(3<<57)|((e%4)<<55)|(1<<41)),('CONTROL','AUTH' if authbit else 'DATA'))
    add(frame(msg=(0,1))) # Messages pause the current half ownership.
    while c.pending:
     lower=0 if len(c.pending)<=1 else rng.getrandbits(256)
     add(frame(lower))
    # Four-beat full request, poison consumes data but never BE.
    add(frame((1<<124)|(0x23<<118)|(1<<102)|3))
    if len(c.pending)>1:add(frame(msg=(32,32)),('POISON','POISON'))
    while c.pending:add(frame(0 if len(c.pending)<=1 else rng.getrandbits(256)))
    # Old-tail/new control overlay is valid only without Auth.
    if not authbit:
     add(frame((1<<124)|(0x23<<118)|(1<<102)))
     add(frame(read),('CONTROL','DATA'))
    add(frame(msg=(0,1)))
   programs.append(fs)
  cursors=[0]*p
  for cycle in range(2000):
   iv=rec=tags=vcs=resp=last=0
   for e in range(p):
    if cursors[e]<len(programs[e]):
     iv|=1<<e;rec|=programs[e][cursors[e]]<<(e*544);tags|=((cursors[e]*7+e)&((1<<t)-1))<<(e*t);vcs|=((cursors[e]+e)%v)<<(e*2);resp|=(cursors[e]%2)<<e;last|=(cursors[e]%3==0)<<e
   ready=0 if cycle<6 else rng.getrandbits(p);o=emit(1,auth,iv,rec,tags,vcs,resp,last,ready)
   for e in range(p):cursors[e]+=bool(o[16]>>e&1)
   if all(cursors[e]==len(programs[e]) for e in range(p)) and not any(m.held):break
  else:raise ValueError('drain timeout')
  # Holding cancellation, then invalid input while old output is protected.
  emit(1,auth,(1<<p)-1,packed([frame(read)]*p,544),0,0,0,0,0);emit(0,auth,0,0,0,0,0,0,0)
  for bad in range(4):
   emit(0,auth,0,0,0,0,0,0,0)
   emit(1,auth,(1<<p)-1,packed([frame(read)]*p,544),0,0,0,0,0)
   invalid=[frame(msg=(255,None)),frame(15<<252),frame(msg=(32,None)),frame(6<<252)][bad]
   emit(1,auth,(1<<p)-1,packed([invalid]*p,544),0,0,0,0,0)
   for _ in range(4):emit(1,auth,(1<<p)-1,packed([frame(read)]*p,544),0,0,0,0,(1<<p)-1)
  if v<4:
   emit(0,auth,0,0,0,0,0,0,0);emit(1,auth,(1<<p)-1,packed([frame(read)]*p,544),0,packed([3]*p,2),0,0,0)
 emit(0,0,0,0,0,0,0,0,0)
 if not all(cov['classes']) or not cov['resets_held'] or not all(cov['ports_errors']):raise ValueError('missing coverage '+str(cov))
 path.write_text(''.join(' '.join(format(x,'x') for x in row)+'\n' for row in rows));return cov

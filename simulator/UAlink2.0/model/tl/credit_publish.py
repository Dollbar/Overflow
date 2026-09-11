"""Finite local FC publication buffer. Pending includes held, unsent proposals.
This does not prove receive-buffer capacities or validate upstream retirement ownership.
"""
def decode(word):
 grants=[0]*20
 for group,(pos,bits) in enumerate(((22,3),(16,3),(8,5),(0,5))):
  field=(word>>pos)&((1<<(bits+3))-1);lane=1+((field>>bits)&3) if field>>(bits+2) else 0
  grants[5*group+lane]=field&((1<<bits)-1)
 return grants
class Publisher:
 def __init__(self,width=8):
  if type(width) is not int or not 1<=width<=16:raise ValueError('WIDTH1..16')
  self.width=width;self.pending=[0]*20;self.pointer=[0]*4;self.active=False;self.done=False;self.shared=False;self.valid=False;self.complete=False;self.word=0
 def output(self,*,start=False,capacities=None,shared=False,release_valid=False,release=None,send=False,reset=False):
  cap=capacities if capacities is not None else [0]*20;rel=release if release is not None else [0]*20
  if len(cap)!=20 or len(rel)!=20 or any(type(x) is not int or not 0<=x<1<<self.width for x in cap) or any(type(x) is not int or not 0<=x<16 for x in rel):raise ValueError('20 width-sized capacities / 4-bit releases')
  config_ok=shared or (any(cap[10:15]) and any(cap[15:20]));sr=not reset and not self.active and config_ok
  rr=not reset and self.done and all(x+y<1<<(self.width+1) for x,y in zip(self.pending,rel));valid=self.valid and not reset
  return dict(valid=valid,complete=self.complete if valid else False,word=self.word if valid else 0,shared=self.shared if valid else False,taken=bool(valid and send),grants=decode(self.word) if valid and not self.complete else [0]*20,start_ready=bool(sr),start_taken=bool(start and sr),config_error=bool(not reset and start and not self.active and not config_ok),release_ready=bool(rr),release_taken=bool(release_valid and rr))
 def step(self,*,start=False,capacities=None,shared=False,release_valid=False,release=None,send=False,reset=False):
  out=self.output(start=start,capacities=capacities,shared=shared,release_valid=release_valid,release=release,send=send,reset=reset)
  if reset:self.__init__(self.width);return out
  old=self.pending[:];rel=release if release is not None else [0]*20
  if out['start_taken']:
   self.active=True;self.shared=bool(shared);self.pending=list(capacities);self.pointer=[0]*4
  else:self.pending=[n+(rel[i] if out['release_taken'] else 0)-(out['grants'][i] if out['taken'] else 0) for i,n in enumerate(old)]
  if out['taken']:
   if self.complete:self.done=True
   else:
    for g in range(4):
     for lane in range(5):
      if out['grants'][g*5+lane]:self.pointer[g]=(lane+1)%5
   self.valid=False;self.word=0;self.complete=False
  elif not self.valid and self.active and not out['start_taken']:
   if any(old):
    self.word=0
    for g,(pos,bits) in enumerate(((22,3),(16,3),(8,5),(0,5))):
     for offset in range(5):
      lane=(self.pointer[g]+offset)%5
      if old[g*5+lane]:
       quantity=min(old[g*5+lane],(1<<bits)-1);field=quantity if lane==0 else quantity|((lane-1)<<bits)|(1<<(bits+2));self.word|=field<<pos;break
    self.valid=True;self.complete=False
   elif not self.done:self.valid=True;self.complete=True;self.word=0
  return out

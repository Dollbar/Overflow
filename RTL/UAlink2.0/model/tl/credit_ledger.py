"""20 logical credit classes mapped onto physical counters.
Local receive is an authorized atomic event; finish/shared belong to that event.
Duplicate wire completion policy and fatal latching belong to the controller.
Slots: each of RequestCMD/ResponseCMD/RequestData/ResponseData has Pool,VC0..3.
Shared Data Pool uses physical slot10, slot15 becomes zero; its capacity is W+1 bits.
"""
class Ledger:
 def __init__(self,bits):
  if type(bits) is not int or bits<1:raise ValueError('positive width required')
  self.bits=bits;self.limit=(1<<bits)-1;self.capacity=[0]*20;self.available=[0]*20;self.done=False;self.shared=False
 def step(self,grants,demands,receive=False,send=False,finish=False,shared=False,reset=False):
  if reset:
   self.capacity=[0]*20;self.available=[0]*20;self.done=False;self.shared=False
   return dict(allowed=False,taken=False,receive_error=False)
  if len(grants)!=20 or len(demands)!=20 or any(type(x) is not int or not 0<=x<=self.limit for x in list(grants)+list(demands)):raise ValueError('20 unsigned width-sized quantities required')
  adds=list(grants) if receive else [0]*20;wants=list(demands)
  if self.shared:
   adds[10]+=adds[15];adds[15]=0;wants[10]+=wants[15];wants[15]=0
  total=[a+g for a,g in zip(self.available,adds)]
  limits=self.capacity if self.done else [self.limit]*20
  error=any(a>c for a,c in zip(total,limits))
  completing=bool(receive and finish and not self.done)
  if completing and not shared and (sum(total[10:15])==0 or sum(total[15:20])==0):error=True
  allowed=self.done and not error and all(q<=a for q,a in zip(wants,self.available))
  taken=bool(send and allowed)
  if not error:
   self.available=[a-(q if taken else 0) for a,q in zip(total,wants)]
   if not self.done:self.capacity=[c+g for c,g in zip(self.capacity,adds)]
   if completing:
    self.done=True;self.shared=bool(shared)
    if self.shared:
     self.capacity[10]+=self.capacity[15];self.capacity[15]=0
     self.available[10]+=self.available[15];self.available[15]=0
  return dict(allowed=bool(allowed),taken=taken,receive_error=bool(error))

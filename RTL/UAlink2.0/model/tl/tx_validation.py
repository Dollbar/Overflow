"""Tx proposal/commit assembly from frozen sequence, packing and content models.
Invalid local proposals do not commit; this is not a receiver fatal policy.
"""
from copy import deepcopy
from tl_sequence import Sequencer
from tl_tenure import derive_control
from tl_content import Content
from tl_packing_budget import PackingBudget
C={'CONTROL':0,'DATA':1,'BYTE_ENABLE':2,'NOP':3,'MESSAGE':4,'POISON':5,'AUTH':6}
class TxValidation:
 def __init__(self,auth=False):
  self.auth=auth;self.sequence=Sequencer(auth=auth);self.content=Content();self.budget=PackingBudget()
 def step(self,lower=0,upper=0,msg=0,transfer=False,reset=False):
  if reset:self.__init__(self.auth);return dict(allowed=False,classes=(7,7))
  seq=deepcopy(self.sequence);content=deepcopy(self.content);budget=deepcopy(self.budget)
  try:
   messages=tuple((w&255) if (msg>>i)&1 else None for i,w in enumerate((lower,upper)))
   desc=derive_control(lower) if len(seq.pending)<=1 and messages[0] is None else dict(fields=0,tenure=(),records=[])
   classes=seq.step(msg=messages,fields=desc['fields'],tenure=desc['tenure'])
   rq=sum(r['kind'] in (1,3) for r in desc['records']);rs=sum(r['kind'] in (2,4,5) for r in desc['records'])
   allowed=rq<=budget.available[0] and rs<=budget.available[1] and content.step(tuple(C[x] for x in classes),(lower,upper),desc['fields'])['allowed']
   if allowed:budget.step(rq,rs,transfer=True)
  except ValueError:allowed=False
  if allowed and transfer:self.sequence=seq;self.content=content;self.budget=budget
  return dict(allowed=bool(allowed),classes=tuple(C[x] for x in classes) if allowed else (7,7))

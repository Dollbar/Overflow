"""Common2.0 confirmed tenure: credits returned only upon later storage retirement.
Data pair credits attach to second half; CMD attaches to last Data/BE (or header
when no tenure). This conservative release ordering is a local implementation policy.
"""
from copy import deepcopy
from dataclasses import dataclass
from tl_sequence import Sequencer
from credit_context import decode_context
@dataclass(frozen=True)
class ReleaseToken:
 kind:str
 slot:int
 reserve:bool
 release_data:bool
 release_cmd:bool
class ReceiveContext:
 def __init__(self,auth=False):self.sequence=Sequencer(auth=auth);self.pending=()
 def step(self,lower=0,*,msg=(None,None),transfer=True,reset=False):
  if reset:
   self.sequence.step(reset=True);self.pending=();return dict(classes=('RESET','RESET'),demands=(0,)*20,releases=(0,)*20,store=False)
  seq=deepcopy(self.sequence);queue=list(self.pending);demands=[0]*20;release=[0]*20;decoded=dict(fields=0,tenure=())
  if len(queue)<=1 and msg[0] is None:
   decoded,tokens,demands=decode_context(lower);index=0
   for record in decoded['records']:
    count=len(record['tenure'])
    if count:
     for j in range(count):
      token=tokens[index+j];queue.append(ReleaseToken(token.kind,token.slot,token.reserve,token.kind=='D' and not token.reserve,j==count-1))
     index+=count
    else:
     # Decode this actual isolated field again to identify the header-only slot.
     _,_,single=decode_context(lower>>(32*record['sector']) & ((1<<(32*(1,4,2,2,1,1)[record['kind']]))-1))
     release=[a+b for a,b in zip(release,single)]
  classes=seq.step(msg=msg,fields=decoded['fields'],tenure=decoded['tenure'])
  store=bool(any(demands))
  for kind in classes:
   if kind not in ('DATA','BYTE_ENABLE','POISON'):continue
   store=True;t=queue.pop(0)
   if ('B' if kind=='BYTE_ENABLE' else 'D')!=t.kind:raise ValueError('release metadata mismatch')
   if t.reserve:demands[t.slot]+=1
   if t.release_data:release[t.slot]+=1
   if t.release_cmd:release[t.slot-10]+=1
  if tuple(t.kind for t in queue)!=seq.pending:raise ValueError('release remainder mismatch')
  if transfer:self.sequence=seq;self.pending=tuple(queue)
  return dict(classes=classes,demands=tuple(demands),releases=tuple(release),store=store)

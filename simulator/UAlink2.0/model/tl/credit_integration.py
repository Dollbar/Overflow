"""Joint full-Flit receiver and local transmit-credit transaction model.
Repeated completion messages are diagnostic only; first completion locks mode.
This is an explicit local policy, not a claim of normative duplicate-message rules.
"""
import copy
from tl_sequence import Sequencer
from tl_tenure import derive_control
from tl_content import Content
from tl_packing_budget import PackingBudget
from credit_events import decode
from credit_ledger import Ledger
CODES=dict(CONTROL=0,DATA=1,BYTE_ENABLE=2,NOP=3,MESSAGE=4,POISON=5,AUTH=6,RESET=7)
class Integrated:
 def __init__(self,bits=16,auth=False):
  if bits<8:raise ValueError('wire event accumulation requires at least eight bits')
  self.bits=bits;self.auth=bool(auth);self.sequence=Sequencer(auth=self.auth);self.content=Content();self.budget=PackingBudget();self.ledger=Ledger(bits);self.fatal=False
 def step(self,lower=0,upper=0,msg=0,receive=False,send=False,demands=None,reset=False):
  empty=dict(rx_allowed=False,rx_taken=False,rx_rejected=False,tx_allowed=False,tx_taken=False,classes=(7,7),init_repeat=False,init_conflict=False)
  if reset:self.__init__(self.bits,self.auth);return empty
  if self.fatal:return dict(empty,rx_rejected=bool(receive))
  messages=tuple((word&255) if (msg>>i)&1 else None for i,word in enumerate((lower,upper)))
  is_control=len(self.sequence.pending)<=1 and messages[0] is None
  events=decode(lower,upper,msg,is_control)
  sequence=copy.deepcopy(self.sequence);content=copy.deepcopy(self.content);budget=copy.deepcopy(self.budget);ledger=copy.deepcopy(self.ledger)
  full_ok=False;classes=(7,7)
  try:
   desc=derive_control(lower) if is_control else dict(fields=0,tenure=(),records=[])
   proposed=sequence.step(msg=messages,fields=desc['fields'],tenure=desc['tenure'],transfer=True)
   rq=sum(r['kind'] in (1,3) for r in desc['records']);rs=sum(r['kind'] in (2,4,5) for r in desc['records'])
   fit=rq<=budget.available[0] and rs<=budget.available[1]
   content_ok=content.step(tuple(CODES[x] for x in proposed),(lower,upper),desc['fields'],transfer=True)['allowed']
   full_ok=fit and content_ok
   if full_ok:budget.step(rq,rs,transfer=True);classes=tuple(CODES[x] for x in proposed)
  except ValueError:full_ok=False
  flags=[bool((events['shared']>>i)&1) for i in range(2) if (events['init']>>i)&1]
  repeat=bool(flags and (self.ledger.done or len(flags)>1))
  mode=self.ledger.shared if self.ledger.done else (flags[0] if flags else False)
  conflict=any(flag!=mode for flag in flags)
  preview=ledger.step(events['grants'],demands if demands is not None else [0]*20,receive=bool(receive),send=bool(send),finish=bool(flags),shared=mode)
  rx_allowed=full_ok and events['valid'] and not preview['receive_error']
  joint_ok=not receive or rx_allowed
  tx_allowed=preview['allowed'] and joint_ok
  if joint_ok:self.ledger=ledger
  if receive:
   if rx_allowed:self.sequence=sequence;self.content=content;self.budget=budget
   else:self.fatal=True
  return dict(rx_allowed=bool(rx_allowed),rx_taken=bool(receive and rx_allowed),rx_rejected=bool(receive and not rx_allowed),tx_allowed=bool(tx_allowed),tx_taken=bool(send and tx_allowed),classes=classes if rx_allowed else (7,7),init_repeat=bool(receive and repeat),init_conflict=bool(receive and conflict))

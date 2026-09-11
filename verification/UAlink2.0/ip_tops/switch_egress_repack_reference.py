"""Independent one-entry event queues; expected fields use numerical divmod boundaries."""
from collections import deque
import random

def generate(path,ports,vcs):
 rng=random.Random(0x544+ports*7+vcs);queues=[deque() for _ in range(ports)];rows=[];accepted=retired=0
 def emit(reset,iv,records,last,tokens,vc,kind,ready):
  nonlocal accepted,retired,queues
  flatten=lambda xs,w:sum(x<<(p*w) for p,x in enumerate(xs))
  ov=ir=err=ol=ok=0;flits=[0]*ports;msg=[0]*ports;aux=[0]*ports;header=[0]*ports;ot=[0]*ports;oc=[0]*ports
  for p in range(ports):
   bad=bool(iv>>p&1 and vc[p]>=vcs)
   if reset:
    if bad:err|=1<<p
    if not bad and (not queues[p] or ready>>p&1):ir|=1<<p
    if queues[p]:
     rec,ls,tok,v,k=queues[p][0];ov|=1<<p;ol|=ls<<p;ok|=k<<p;ot[p]=tok;oc[p]=v
     upper,flits[p]=divmod(rec,1<<512);upper,msg[p]=divmod(upper,4);header[p],aux[p]=divmod(upper,64)
  rows.append([reset,iv,flatten(records,544),last,flatten(tokens,8),flatten(vc,2),kind,ready,ir,ov,flatten(header,24),flatten(aux,6),flatten(msg,2),flatten(flits,512),ol,flatten(ot,8),flatten(oc,2),ok,err])
  if not reset:queues=[deque() for _ in range(ports)]
  else:
   for p in range(ports):
    if ov>>p&1 and ready>>p&1:queues[p].popleft();retired+=1
    if iv>>p&1 and ir>>p&1:queues[p].append((records[p],last>>p&1,tokens[p],vc[p],kind>>p&1));accepted+=1
  return ir
 zeros=[0]*ports;full=(1<<ports)-1
 emit(0,full,[(1<<544)-1]*ports,full,[255]*ports,[3]*ports,full,full)
 # Exact per-bit endianness, including 24/6/2/512 boundaries, independently per physical port.
 for bit in range(544):
  record=[1<<((bit+p)%544) for p in range(ports)];vc=[(bit+p)%vcs for p in range(ports)];tokens=[(bit*13+p)&255 for p in range(ports)]
  emit(1,full,record,bit&full,tokens,vc,(bit//3)&full,full)
  if bit%17==0:emit(1,0,zeros,full,[255]*ports,[3]*ports,full,0)
 emit(1,0,zeros,0,zeros,zeros,0,full)
 # Legal multi-beat streams with per-port held candidates and independent downstream stalls.
 pending=[None]*ports;remaining=[0]*ports;tags=[0]*ports;classes=[0]*ports;vchan=[0]*ports
 for cycle in range(1500):
  if cycle in [399,1001]:
   emit(0,full,zeros,full,zeros,zeros,full,full);pending=[None]*ports;remaining=[0]*ports;continue
  for p in range(ports):
   if pending[p] is None and rng.randrange(4):
    if remaining[p]==0:remaining[p]=rng.randrange(1,6);tags[p]=rng.randrange(256);classes[p]=rng.randrange(2);vchan[p]=rng.randrange(vcs)
    pending[p]=(rng.getrandbits(544),remaining[p]==1,tags[p],vchan[p],classes[p])
  records=zeros.copy();tokens=zeros.copy();vc=zeros.copy();iv=last=kind=0
  for p,x in enumerate(pending):
   if x is not None:
    records[p],ls,tokens[p],vc[p],k=x;iv|=1<<p;last|=ls<<p;kind|=k<<p
  take=emit(1,iv,records,last,tokens,vc,kind,rng.randrange(1<<ports))&iv
  for p in range(ports):
   if take>>p&1:pending[p]=None;remaining[p]-=1
 # Drain, then exercise invalid VC without destroying an older valid output.
 emit(1,0,zeros,0,zeros,zeros,0,full)
 if vcs<4:
  emit(1,full,[(1<<544)-1]*ports,full,[128]*ports,zeros,full,0)
  for _ in range(3):emit(1,full,zeros,0,zeros,[vcs]*ports,0,0)
  emit(1,full,zeros,0,zeros,[vcs]*ports,0,full)
 emit(0,0,zeros,0,zeros,zeros,0,0)
 emit(1,0,zeros,0,zeros,zeros,0,full)
 path.write_text(''.join(' '.join(format(x,'x') for x in row)+'\n' for row in rows))
 return {'rows':len(rows),'accepted_events_including_reset_cancel':accepted,'retired_events':retired,'walking_bits_per_port':544}

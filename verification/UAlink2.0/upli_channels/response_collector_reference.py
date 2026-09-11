"""Independent event/port-queue oracle; no RTL or internal DUT state is read."""
import random

def generate(path,ports):
 rng=random.Random(0x925+ports);lines=[];lock=[None,None];sticky=0;retired=[[[0]*5 for _ in range(ports)] for _ in range(2)]
 def row(reset,stop,sv,sp,hv,cv,vc,pool,account,ready,rd,wr):
  nonlocal lock,sticky
  selected=[lock[c] if lock[c] is not None else sp[c] for c in range(2)]
  enabled=[lock[c] is not None or bool(sv>>c&1) for c in range(2)]
  error=0
  for c in range(2):
   if reset and enabled[c] and (selected[c]>=ports or ((hv>>c&1) and account[c]!=(4 if pool>>c&1 else vc[c]))):error|=1<<c
  active=bool(reset and not stop and not error and not sticky)
  valid=sum(int(active and enabled[c] and bool(hv>>c&1) and bool(cv>>c&1))<<c for c in range(2))
  take=valid&ready
  payloads=[rd if valid&1 else 0,wr if valid&2 else 0]
  pack=lambda vals,w:sum(v<<(w*c) for c,v in enumerate(vals))
  outport=pack(selected,2) if reset else 0
  fields=[reset,stop,sv,pack(sp,2),hv,cv,pack(vc,2),pool,pack(account,3),ready,rd,wr,outport,valid,take,payloads[0],payloads[1],pack(vc,2) if valid==3 else sum(vc[c]<<(2*c) for c in range(2) if valid>>c&1),pool&valid,sum(account[c]<<(3*c) for c in range(2) if valid>>c&1),error, int(reset and bool(error or sticky))]
  lines.append(' '.join(format(x,'x') for x in fields))
  if not reset:lock=[None,None];sticky=0
  else:
   sticky|=error
   for c in range(2):
    if take>>c&1:
     retired[c][selected[c]][account[c]]+=1;lock[c]=None
    elif active and enabled[c] and hv>>c&1:lock[c]=selected[c]
 for _ in range(3):row(0,0,3,[3,3],3,3,[3,3],3,[4,4],3,2**619-1,2**101-1)
 # Every payload bit and every account/port, interrupted by stalled credit and changed selector.
 for c,width in [(0,619),(1,101)]:
  for bit in range(width):
   port=bit%ports;vc=[bit%4,(bit+1)%4];pool=(bit//4)%4;ac=[4 if pool>>q&1 else vc[q] for q in range(2)]
   sp=[port,port];payload=[0,0];payload[c]=1<<bit
   for k in range(5):
    row(1,int(k==2),3,sp if k==0 else [(port+1)%ports]*2,3,0 if k==0 else 3,vc,pool,ac,0 if k<4 else 3,*payload)
 # Random stalls and explicit no-valid selection, with each protected head stable while locked.
 records=[None,None]
 for cycle in range(1500):
  sp=[rng.randrange(ports),rng.randrange(ports)];sv=rng.randrange(4);vc=[];pool=0;ac=[];data=[];hv=0
  for c,width in [(0,619),(1,101)]:
   if lock[c] is None:records[c]=(rng.randrange(4),rng.randrange(2),rng.getrandbits(width),rng.randrange(4)!=0)
   v,p,d,h=records[c];vc.append(v);pool|=p<<c;ac.append(4 if p else v);data.append(d);hv|=int(h)<<c
  row(1,int(cycle%31==0),sv,sp,hv,rng.randrange(4),vc,pool,ac,rng.randrange(4),*data)
 # Reset cancellation then each metadata mismatch and illegal physical selector.
 for c in range(2):
  row(0,0,0,[0,0],0,0,[0,0],0,[0,0],0,0,0)
  ac=[0,0];ac[c]=4
  row(1,0,3,[0,0],3,3,[0,0],0,ac,3,17,19)
  row(1,0,3,[0,0],3,3,[0,0],0,[0,0],3,17,19)
 if ports<4:
  row(0,0,0,[0,0],0,0,[0,0],0,[0,0],0,0,0)
  row(1,0,3,[ports,0],3,3,[0,0],0,[0,0],3,17,19)
 row(0,0,0,[0,0],0,0,[0,0],0,[0,0],0,0,0)
 row(1,0,3,[0,0],3,3,[0,0],0,[0,0],3,17,19)
 path.write_text('\n'.join(lines)+'\n')
 return {'rows':len(lines),'retired_by_channel_port_account':retired,'walking_payload_bits':720}

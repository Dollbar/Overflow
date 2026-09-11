"""Independent chronological journal for actual ordered-RX and credit trace."""
from collections import deque

def check(path,ports,width,caps,cw=4):
 names='cycle rstn cc bc send receive port vc pool data cport ready accepted diag hv cv head hvc hpool account order oe os counts pending rv rp rvc rn done balances bdone berr'.split()
 queues=[deque() for _ in range(ports)];owed=[deque() for _ in range(ports)]
 count=[0]*(5*ports);bal=[0]*(5*ports);initial=[0]*(5*ports);confirmed=[0]*ports;filter_count=[0]*ports
 prev=None;prev_diag=0;initial_last=[-1]*ports;accepted=retired=returned=resets=overlap=0;maxfill=[0]*ports;last_tuple=[None]*ports;switches=0
 def fail(c,m):raise ValueError(f'cycle {c}: {m}')
 for line in path.read_text().splitlines():
  if not line.startswith('TRACE '):continue
  values=[int(x,16) for x in line.split()[1:]]
  if len(values)!=len(names):raise ValueError('trace shape')
  x=dict(zip(names,values));cy=x['cycle']
  if not x['rstn']:
   queues=[deque() for _ in range(ports)];owed=[deque() for _ in range(ports)];count=[0]*(5*ports);bal=[0]*(5*ports);initial=[0]*(5*ports);confirmed=[0]*ports;filter_count=[0]*ports;prev=None;prev_diag=0;initial_last=[-1]*ports;resets+=1;continue
  flat=lambda a,w:sum(n<<(k*w) for k,n in enumerate(a))
  if x['counts']!=flat(count,cw):fail(cy,'physical counts mismatch')
  if x['balances']!=flat(bal,cw):fail(cy,'actual sender bank balance mismatch')
  if x['bdone']!=sum(n<<p for p,n in enumerate(confirmed)):fail(cy,'bank init filter mismatch')
  if x['berr'] or x['oe'] or x['os']:fail(cy,'unexpected bank/order error')
  if x['accepted']!=int(prev is not None):fail(cy,'registered acceptance misaligned')
  if x['diag']!=prev_diag:fail(cy,'registered diagnostic mismatch')
  expected_order=[len(q)-int(prev is not None and prev[0]==p) for p,q in enumerate(queues)]
  if x['order']!=flat(expected_order,cw+3):fail(cy,'order_count + pending != occupancy')
  for p in range(ports):
   if not 0<=len(queues[p])<=sum(caps[p*5:p*5+5]):fail(cy,'declared capacity violated')
   maxfill[p]=max(maxfill[p],len(queues[p]))
   if x['done']>>p&1:
    if initial[p*5:p*5+5]!=caps[p*5:p*5+5] or initial_last[p]>=cy:fail(cy,'init done before all initial credits')
   if x['rv']>>p&1:
    pool=x['rp']>>p&1;vc=x['rvc']>>(2*p)&3;n=(x['rn']>>(2*p)&3)+1;a=p*5+(4 if pool else vc)
    if initial[a]<caps[a]:
     if pool and vc!=0:fail(cy,'initial pool VC not zero')
     initial[a]+=n;initial_last[p]=cy
     if initial[a]>caps[a]:fail(cy,'excess initial credit')
    else:
     for _ in range(n):
      if not owed[p] or owed[p].popleft()!=(vc,pool):fail(cy,'credit lacks matching prior retirement')
     returned+=n
    bal[a]+=n
   if not confirmed[p]:
    filter_count[p]=filter_count[p]+1 if x['done']>>p&1 else 0
    if filter_count[p]>=2:confirmed[p]=1
  if (x['rv']|x['done'])>>ports:fail(cy,'unused port emitted credit')
  cp=x['cport'];has=cp<ports and expected_order[cp]>0
  expaccount=4 if has and queues[cp][0][2] else queues[cp][0][1] if has else 0
  if x['account']!=expaccount:fail(cy,'head account differs from actual arrival order')
  if x['hv']:
   if not has:fail(cy,'head before order ownership')
   tup=queues[cp][0]
   if (x['head'],x['hvc'],x['hpool'])!=(tup[3],tup[1],tup[2]):fail(cy,'full data/VC/pool reordered or corrupted')
  if x['cv'] and not x['hv']:fail(cy,'consume valid without head')
  pop=bool(x['cv'] and x['ready'])
  # Incoming acceptance uses OLD per-account count, before this edge's pop.
  p=x['port'];vc=x['vc'];pool=x['pool'];a=p*5+(4 if pool else vc)
  prev_diag=0 if not x['receive'] else 1 if p>=ports else 2 if not(x['cc'] and x['bc']) else 3 if not(x['done']>>p&1) else 4 if count[a]>=caps[a] else 0
  take=bool(x['receive'] and p<ports and x['cc'] and x['bc'] and x['done']>>p&1 and count[a]<caps[a])
  if x['send']:
   if not take or not confirmed[p]:fail(cy,'credited sender emitted unreceivable beat')
   # Returns sampled on this edge cannot be used by this edge's send.
   oldbal=(x['balances']>>(a*cw))&((1<<cw)-1)
   if oldbal<1:fail(cy,'sender borrowed same-edge return')
   bal[a]-=1
  if pop:
   tup=queues[cp].popleft();count[cp*5+(4 if tup[2] else tup[1])]-=1;owed[cp].append((tup[1],tup[2]));retired+=1
   if last_tuple[cp] is not None and last_tuple[cp]!=(tup[1],tup[2]):switches+=1
   last_tuple[cp]=(tup[1],tup[2])
  prev=(p,vc,pool,x['data']) if take else None
  if take:queues[p].append(prev);count[a]+=1;accepted+=1
  overlap+=int(pop and take)
  if any(not 0<=b<=c for b,c in zip(bal,caps)):fail(cy,'credit over/underflow')
 if any(queues) or any(owed):raise ValueError('final drain incomplete')
 if bal!=caps:raise ValueError('final sender credits not restored')
 if not accepted or not retired or not overlap or not switches:raise ValueError('vacuous coverage')
 return dict(accepted=accepted,retired=retired,returned=returned,resets=resets,simultaneous_receive_consume=overlap,cross_account_transitions=switches,max_port_occupancy=maxfill,passed=True)

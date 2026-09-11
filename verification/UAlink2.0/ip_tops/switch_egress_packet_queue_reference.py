"""Independent public-event packet oracle: complete words, descriptor order, capacity ledger.
Does not reproduce the reused FIFO's read pipeline or inspect DUT internals.
"""
from collections import deque

def check(path,p,w,d,t,caps,expect_bad=False):
 names='cycle rst req routes units ready wvalid wdata wlast wtoken rtoken reqready grant gunits admit wready valid data last token release runits relaccepted available reserved qr stored completed busy error sticky reserr qerr'.split()
 queues=[deque() for _ in range(p)];active=[None]*p;halt=[False]*p;credit=list(caps);rr=[deque(range(p)) for _ in range(p)];latency=[0]*p
 count={'cycles':0,'reserved_packets':0,'written_words':0,'retired_words':0,'released_packets':0,'released_units':0,'canceled_packets':0,'bad_edges':0,'stall_words':0,'write_bubbles':0,'concurrent_release_reserve':0,'final_write_pop':0};prevstall=[None]*p
 def fail(c,msg):raise ValueError(f'QUEUE_MISMATCH cycle={c}: {msg}')
 def pieces(v,width):return [(v>>(i*width))&((1<<width)-1) for i in range(p)]
 for line in path.read_text().splitlines():
  cells=line.split()
  if len(cells)!=len(names):raise ValueError('trace columns')
  try:a={n:int(v,10 if n=='cycle' else 16) for n,v in zip(names,cells)}
  except ValueError:raise ValueError('trace contains X/Z')
  c=a['cycle'];count['cycles']+=1
  def equal(x,y,n):
   if x!=y:fail(c,f'{n} actual={x!r} expected={y!r}')
  reserved=[sum(q['units'] for q in qs) for qs in queues]
  stored=[sum(len(q['words'])-q['read'] for q in qs) for qs in queues]
  complete=[sum(q['complete'] for q in qs) for qs in queues]
  equal(pieces(a['qr'],w),reserved,'queue reserved');equal(pieces(a['stored'],w),stored,'stored words');equal(pieces(a['completed'],w),complete,'completed packets')
  equal(pieces(a['available'],w),credit,'reservation available');equal(pieces(a['reserved'],w),[caps[e]-credit[e] for e in range(p)],'reservation used')
  if not a['rst']:
   for name in ('grant','reqready','admit','wready','valid','data','last','token','release','runits','relaccepted','busy','error','sticky','qerr','reserr'):equal(a[name],0,'reset '+name)
   count['canceled_packets']+=sum(map(len,queues));queues=[deque() for _ in range(p)];active=[None]*p;halt=[False]*p;credit=list(caps);rr=[deque(range(p)) for _ in range(p)];prevstall=[None]*p;latency=[0]*p
   continue
  admit=sum((not halt[e] and active[e] is None and reserved[e]<caps[e])<<e for e in range(p));equal(a['admit'],admit,'admit only old state')
  equal(a['busy'],sum((active[e] is not None)<<e for e in range(p)),'active writer')
  equal(a['sticky'],sum(halt[e]<<e for e in range(p)),'sticky error')
  expectedgrant=0;expectedunits=0;expectedready=0
  for e in range(p):
   if not (admit>>e)&1:continue
   for s in rr[e]:
    n=(a['units']>>(s*w))&((1<<w)-1);route=(a['routes']>>(s*p))&((1<<p)-1)
    if ((a['req']>>s)&1) and route==(1<<e) and 1<=n<=credit[e]:
     expectedgrant|=1<<(e*p+s);expectedunits|=n<<(e*w);expectedready|=1<<s;break
  equal(a['grant'],expectedgrant,'RR grant');equal(a['gunits'],expectedunits,'whole grant units');equal(a['reqready'],expectedready,'request accepted')
  equal(a['reserr'],0,'reservation errors');equal(a['relaccepted'],a['release'],'actual returned credit accepted')
  expected_error=0;expected_wready=0
  for e in range(p):
   bit=1<<e;act=active[e];wv=bool(a['wvalid']&bit);tok=(a['wtoken']>>(e*t))&((1<<t)-1);wl=bool(a['wlast']&bit)
   bad=wv and (act is None or tok!=act['token'] or wl!=(len(act['words'])+1==act['units']) or stored[e]>=caps[e])
   if not halt[e] and bad:expected_error|=bit
   blocked=halt[e] or bad
   wr=not blocked and act is not None and stored[e]<caps[e];expected_wready|=int(wr)<<e
   v=bool(a['valid']&bit);word=(a['data']>>(e*d))&((1<<d)-1);ot=(a['token']>>(e*t))&((1<<t)-1);last=bool(a['last']&bit)
   rel=bool(a['release']&bit);ru=(a['runits']>>(e*w))&((1<<w)-1)
   if not v:equal((word,ot,last),(0,0,False),'invalid output zero')
   if halt[e]:equal((v,rel,ru),(False,False,0),'fail-stop output')
   if v:
    if not queues[e] or not queues[e][0]['complete']:fail(c,'partial packet was published')
    q=queues[e][0];equal((word,ot,last),(q['words'][q['read']],q['token'],q['read']==q['units']-1),'full stored word/token/last')
   current=(word,ot,last) if v else None
   if prevstall[e] is not None and not halt[e]:equal(current,prevstall[e],'backpressure holds complete output')
   prevstall[e]=current if v and not (a['ready']&bit) else None
   if prevstall[e] is not None:count['stall_words']+=1
   equal(rel,v and bool(a['ready']&bit) and last,'last handshake release');equal(ru,queues[e][0]['units'] if rel else 0,'original whole units release')
   if complete[e] and not v and not halt[e]:
    latency[e]+=1
    if latency[e]>5:fail(c,'committed head not published within registered FIFO bound')
   else:latency[e]=0
   if act is not None and not wv:count['write_bubbles']+=1
   if bad and not halt[e]:count['bad_edges']+=1
   # Reservation service commits its actual grant and actual release independently.
   grant=(a['grant']>>(e*p))&((1<<p)-1);n=(a['gunits']>>(e*w))&((1<<w)-1)
   credit[e]+=ru-n
   if grant:
    s=grant.bit_length()-1
    while rr[e][0]!=s:rr[e].rotate(-1)
    rr[e].rotate(-1)
   if halt[e]:
    if grant:fail(c,'unexpected halted port charged grant')
    continue
   if rel and grant:count['concurrent_release_reserve']+=1
   if v and a['ready']&bit:
    queues[e][0]['read']+=1;count['retired_words']+=1
    if rel:queues[e].popleft();count['released_packets']+=1;count['released_units']+=ru
   if bad:
    halt[e]=True
    if grant:fail(c,'unexpected invalid input coincides with charged grant')
    continue
   if wv and wr:
    act['words'].append((a['wdata']>>(e*d))&((1<<d)-1));count['written_words']+=1
    if len(act['words'])==act['units']:
     act['complete']=True;active[e]=None
     if v and a['ready']&bit:count['final_write_pop']+=1
   if grant:
    q={'units':n,'token':(a['rtoken']>>(e*t))&((1<<t)-1),'words':[],'read':0,'complete':False};queues[e].append(q);active[e]=q;count['reserved_packets']+=1
  equal(a['error'],expected_error,'input error');equal(a['wready'],expected_wready,'write qualification');equal(a['qerr'],int(bool(expected_error or a['sticky'])),'aggregate diagnostic')
 if any(queues):raise ValueError('QUEUE_MISMATCH final queue did not drain')
 if count['reserved_packets']!=count['released_packets']+count['canceled_packets']:raise ValueError('descriptor conservation')
 if bool(count['bad_edges'])!=expect_bad:raise ValueError('illegal input coverage')
 for n in ('reserved_packets','written_words','retired_words','stall_words','write_bubbles'):
  if not count[n]:raise ValueError('missing coverage '+n)
 return count

"""Independent public-event model: physically disjoint (class,VC,egress) deques and RR.
No DUT internal state is used. Accepted body bytes are the immutable output oracle.
"""
from collections import deque

def check(path,p,v,w,d,t,caps,bad=0):
 n=2*v*p;names='cycle rst hv route units ht vc hr bv bd bl bt ready hready bready valid data last token release runits available reserved qr stored complete busy herror berror source_sticky qerror qsticky error unused'.split()
 qs=[deque() for _ in range(n)];active=[None]*n;owner=[None]*p;halt=[False]*n;source_halt=[False]*p;rr=[deque(range(p)) for _ in range(n)];credit=list(caps);oldstall=[None]*n;delay=[0]*n
 cov={'cycles':0,'headers':0,'written':0,'retired_words':0,'released_packets':0,'released_units':0,'canceled':0,'response_while_request_full':0,'other_vc_while_vc0_full':0,'header_blocked_by_owner':0,'body_ignores_current_header':0,'stall':0,'body_bubble':0,'bad_edges':0,'header_rejections':0,'slot_headers':[0]*n}
 def pieces(x,width,count):return [(x>>(s*width))&((1<<width)-1) for s in range(count)]
 for line in path.read_text().splitlines():
  z=line.split()
  if len(z)!=len(names):raise ValueError('VC_QUEUE_MISMATCH trace columns')
  try:a={k:int(x,10 if k=='cycle' else 16) for k,x in zip(names,z)}
  except ValueError:raise ValueError('VC_QUEUE_MISMATCH X/Z')
  c=a['cycle'];cov['cycles']+=1
  def eq(x,y,what):
   if x!=y:raise ValueError(f'VC_QUEUE_MISMATCH cycle={c}: {what} actual={x!r} expected={y!r}')
  use=[sum(q['units'] for q in row) for row in qs];stored=[sum(len(q['words'])-q['read'] for q in row) for row in qs];complete=[sum(q['complete'] for q in row) for row in qs]
  eq(pieces(a['available'],w,n),credit,'partition free');eq(pieces(a['reserved'],w,n),[caps[k]-credit[k] for k in range(n)],'partition reservation');eq(pieces(a['qr'],w,n),use,'queue reservation');eq(pieces(a['stored'],w,n),stored,'stored');eq(pieces(a['complete'],w,n),complete,'complete')
  if not a['rst']:
   for name in ('hready','bready','valid','data','last','token','release','runits','busy','herror','berror','source_sticky','qerror','qsticky','error'):eq(a[name],0,'reset '+name)
   cov['canceled']+=sum(map(len,qs));qs=[deque() for _ in range(n)];active=[None]*n;owner=[None]*p;halt=[False]*n;source_halt=[False]*p;rr=[deque(range(p)) for _ in range(n)];credit=list(caps);oldstall=[None]*n;delay=[0]*n;continue
  eq(a['busy'],sum((q is not None)<<s for s,q in enumerate(owner)),'source owner');eq(a['source_sticky'],sum(x<<s for s,x in enumerate(source_halt)),'source sticky');eq(a['qsticky'],sum(x<<k for k,x in enumerate(halt)),'queue sticky')
  herror=0;berror=0;qerror=0;bready=0;choices=[[] for _ in range(n)];source_bad=[False]*p
  for s in range(p):
   bit=1<<s;vc=(a['vc']>>(s*2))&3;resp=bool(a['hr']&bit);route=(a['route']>>(s*p))&((1<<p)-1);units=(a['units']>>(s*w))&((1<<w)-1);q=owner[s]
   if a['hv']&bit and q is not None:cov['header_blocked_by_owner']+=1
   unowned=q is None and bool(a['bv']&bit)
   if unowned and not source_halt[s]:berror|=bit;source_bad[s]=True
   if q is not None:
    k=q['slot'];wrong=bool(a['bv']&bit) and (((a['bt']>>(s*t))&((1<<t)-1))!=q['token'] or bool(a['bl']&bit)!=(len(q['words'])+1==q['units']))
    if not source_halt[s] and wrong:berror|=bit;qerror|=1<<k;source_bad[s]=True
    if not source_halt[s] and not halt[k] and not wrong:bready|=bit
    if not a['bv']&bit:cov['body_bubble']+=1
    if ((int(resp)*v+vc)*p+(route.bit_length()-1))!=k and a['bv']&bit:cov['body_ignores_current_header']+=1
   if a['hv']&bit and q is None and not source_halt[s] and not unowned:
    if vc>=v or route==0 or route&(route-1):herror|=bit;continue
    e=route.bit_length()-1;k=(int(resp)*v+vc)*p+e
    if not 1<=units<=caps[k]:herror|=bit;continue
    if not halt[k] and active[k] is None and units<=credit[k]:choices[k].append(s)
  cov['header_rejections']+=herror.bit_count()
  eq(a['herror'],herror,'header diagnostic');eq(a['berror'],berror,'body diagnostic');eq(a['qerror'],qerror,'domain error');eq(a['bready'],bready,'saved owner body readiness');eq(a['error'],int(bool(herror or berror or a['source_sticky'] or qerror or a['qsticky'])),'aggregate error')
  winners={};hready=0
  for k in range(n):
   for s in rr[k]:
    if s in choices[k]:winners[k]=s;hready|=1<<s;break
  eq(a['hready'],hready,'per-partition RR/atomic header')
  popped=[]
  for k in range(n):
   bit=1<<k;valid=bool(a['valid']&bit);data=(a['data']>>(k*d))&((1<<d)-1);token=(a['token']>>(k*t))&((1<<t)-1);last=bool(a['last']&bit);release=bool(a['release']&bit);units=(a['runits']>>(k*w))&((1<<w)-1)
   if halt[k]:eq(valid,False,'failed partition blocks only its output')
   if valid:
    if not qs[k] or not qs[k][0]['complete']:raise ValueError(f'VC_QUEUE_MISMATCH cycle={c}: partial/wrong-domain output')
    q=qs[k][0];eq((data,token,last),(q['words'][q['read']],q['token'],q['read']==q['units']-1),'partition complete word/token/last')
   else:eq((data,token,last),(0,0,False),'invalid data zero')
   current=(data,token,last) if valid else None
   if oldstall[k] is not None and not halt[k]:eq(current,oldstall[k],'stable stalled head')
   oldstall[k]=current if valid and not a['ready']&bit else None
   if oldstall[k] is not None:cov['stall']+=1
   if complete[k] and not valid and not halt[k]:
    delay[k]+=1
    if delay[k]>5:raise ValueError(f'VC_QUEUE_MISMATCH cycle={c}: committed queue stalled internally')
   else:delay[k]=0
   eq(release,valid and bool(a['ready']&bit) and last,'only actual last retires capacity');eq(units,qs[k][0]['units'] if release else 0,'exact original units')
   if valid and a['ready']&bit:
    qs[k][0]['read']+=1;cov['retired_words']+=1
    if release:qs[k].popleft();credit[k]+=units;cov['released_packets']+=1;cov['released_units']+=units
  for s in range(p):
   q=owner[s]
   if source_bad[s]:
    cov['bad_edges']+=1;source_halt[s]=True
    if q is not None:halt[q['slot']]=True
   elif q is not None and a['bv']&a['bready']&(1<<s):
    q['words'].append((a['bd']>>(s*d))&((1<<d)-1));cov['written']+=1
    if len(q['words'])==q['units']:q['complete']=True;active[q['slot']]=None;owner[s]=None
  for k,s in winners.items():
   units=(a['units']>>(s*w))&((1<<w)-1);token=(a['ht']>>(s*t))&((1<<t)-1)
   if k>=v*p and caps[k-v*p]>0 and credit[k-v*p]==0:cov['response_while_request_full']+=1
   vc0=(k//(v*p))*(v*p)+(k%p)
   if (k//p)%v!=0 and caps[vc0]>0 and credit[vc0]==0:cov['other_vc_while_vc0_full']+=1
   q={'units':units,'token':token,'words':[],'read':0,'complete':False,'slot':k};qs[k].append(q);active[k]=q;owner[s]=q;credit[k]-=units;cov['headers']+=1;cov['slot_headers'][k]+=1
   while rr[k][0]!=s:rr[k].rotate(-1)
   rr[k].rotate(-1)
 if any(qs) or any(owner):raise ValueError('VC_QUEUE_MISMATCH final drain')
 eq(cov['headers'],cov['released_packets']+cov['canceled'],'packet conservation')
 if bool(cov['bad_edges'])!=(bad in (1,3)):raise ValueError('VC_QUEUE_MISMATCH missing invalid token coverage')
 if bool(cov['header_rejections'])!=(bad in (2,4,5,6)):raise ValueError('VC_QUEUE_MISMATCH header rejection coverage')
 for name in ('headers','written','stall','body_bubble','response_while_request_full','header_blocked_by_owner','body_ignores_current_header'):
  if not cov[name]:raise ValueError('VC_QUEUE_MISMATCH coverage '+name)
 if v>1 and not cov['other_vc_while_vc0_full']:raise ValueError('VC_QUEUE_MISMATCH no cross-VC resource isolation')
 if any(cap>0 and not cov['slot_headers'][k] for k,cap in enumerate(caps)):raise ValueError('VC_QUEUE_MISMATCH untested enabled partition')
 return cov

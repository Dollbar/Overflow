"""Independent local application response and isolation obligation event oracle."""
import random
INPUTS={'rstn':'1','iso':'P','down':'P','up':'P','init':'P','drop':'P','quiet':'1','tv':'1','ts':'2','tp':'2','te':'E','tag':'11','read':'1','beats':'3','cv':'1','cs':'2','ce':'E','rv':'1','re':'E','rr':'1','dr':'1','qv':'1','qs':'2','qp':'2','qe':'E','qt':'11','qr':'1','qb':'3','qstatus':'4'}
OUTPUTS={'isolated':'P','forward':'P','epoch':'E','count':'8','tr':'1','cr':'1','discard':'1','retire':'1','recover_ready':'1','recovered':'1','error':'4','qready':'1','accepted':'1','busy':'1','response_valid':'1','response_slot':'2','response_port':'2','response_epoch':'E','response_tag':'11','response_read':'1','response_num':'2','response_last':'1','response_offset':'2','response_status':'4','response_data':'512','done_valid':'1','done_slot':'2','done_epoch':'E','generator_error':'1'}

def generate(path,ports,capacity,is_switch,unit=0,epoch_width=2):
 rng=random.Random(8031+ports*103+capacity*17+is_switch+unit*91);full=(1<<ports)-1;limit=(1<<epoch_width)-1
 obligations={};isolated=set();epoch=0;cursor=0;held=None;active=None;beat=0;phase='idle';rows=[]
 stats={k:0 for k in ['tracked','normal_retired','late_discarded','dummy_requested','read_beats','write_responses','dummy_done','recoveries','response_stalls','done_stalls','reset_cancelled']}
 def emit(**kw):
  nonlocal obligations,isolated,epoch,cursor,held,active,beat,phase
  x={k:0 for k in INPUTS};x.update(rstn=1,up=full,init=full,quiet=1,te=epoch,ce=epoch,re=(epoch+1)&limit,dr=1,qstatus=8,qr=1,qb=1);x.update(kw)
  reset=bool(x['rstn']);o={k:0 for k in OUTPUTS};trigger={p for p in range(ports)if (x['iso']|x['down'])>>p&1}
  if trigger and not is_switch:trigger=set(range(ports))
  current=isolated|trigger
  picked=held if held is not None else next((s for s in sorted(obligations,key=lambda s:(s-cursor)%capacity)if obligations[s]['port']in current and not obligations[s]['issued']),None)
  desc=obligations[picked]if picked is not None else None
  if unit:
   request=bool(x['qv']);d={'slot':x['qs'],'port':x['qp'],'epoch':x['qe'],'tag':x['qt'],'read':x['qr'],'beats':x['qb'],'status':x['qstatus']};done_ready=bool(x['dr'])
  else:
   request=bool(picked is not None and reset);d=dict(desc,slot=picked,epoch=epoch,status=8)if desc else dict(slot=0,port=0,epoch=epoch,tag=0,read=0,beats=0,status=8);done_ready=reset
  legal=d['status']==8 and 1<=d['beats']<=4 and (d['read']or d['beats']==1)
  ready=reset and phase=='idle' and legal;accept=request and ready
  o['qready']=int(ready)if unit else 0;o['accepted']=int(accept);o['busy']=int(reset and phase!='idle');o['generator_error']=int(reset and request and not legal)
  if reset and phase=='response':
   o.update(response_valid=1,response_slot=active['slot'],response_port=active['port'],response_epoch=active['epoch'],response_tag=active['tag'],response_read=active['read'],response_num=0,response_last=int(beat==active['beats']-1),response_offset=beat if active['read']else 0,response_status=8,response_data=0)
  if reset and phase=='done':o.update(done_valid=1,done_slot=active['slot'],done_epoch=active['epoch'])
  normal=False;good_track=False;recover=False
  if not unit:
   legal_track=x['ts']<capacity and x['ts']not in obligations and x['te']==epoch and x['tp']<ports and 1<=x['beats']<=4 and (x['read']or x['beats']==1)
   hit=x['cs']in obligations and x['ce']==epoch
   normal=bool(reset and x['cv']and hit and obligations[x['cs']]['port']not in current and not obligations[x['cs']]['issued'])
   good_track=bool(reset and x['tv']and legal_track)
   recover=bool(reset and isolated and not obligations and x['quiet']and x['up']==full and x['init']==full and not x['drop']and not trigger and not x['tv']and not x['cv']and not o['done_valid']and epoch<limit and x['re']==epoch+1)
   mask=sum(1<<p for p in current)if reset else 0
   o.update(isolated=mask,forward=(x['up']&x['init']&~x['drop']&~mask&full)if reset else 0,epoch=epoch,count=len(obligations),tr=int(reset and legal_track),cr=int(reset),discard=int(reset and x['cv']and not normal),retire=int(normal),recover_ready=int(recover),recovered=int(x['rv']and recover),error=int(reset and x['tv']and not legal_track)|(int(reset and x['cv']and not hit)<<1)|(int(reset and x['rv']and not recover)<<3))
  rows.append([x[k]for k in INPUTS]+[o[k]for k in OUTPUTS])
  if not reset:
   stats['reset_cancelled']+=int(active is not None)if unit else len(obligations);obligations={};isolated=set();epoch=0;cursor=0;held=None;active=None;beat=0;phase='idle';return o
  if o['response_valid']and not x['rr']:stats['response_stalls']+=1
  if o['done_valid']and not done_ready:stats['done_stalls']+=1
  if not unit:
   isolated=current
   if good_track:obligations[x['ts']]={'port':x['tp'],'tag':x['tag'],'read':x['read'],'beats':x['beats'],'issued':False};stats['tracked']+=1
   if normal:del obligations[x['cs']];stats['normal_retired']+=1
   if o['discard']:stats['late_discarded']+=1
   if request and not ready:held=picked
   if accept:obligations[picked]['issued']=True;cursor=(picked+1)%capacity;held=None
   if o['done_valid']:
    if active['slot']not in obligations or not obligations[active['slot']]['issued']:raise RuntimeError('oracle issued causality')
    del obligations[active['slot']]
   if x['rv']and recover:isolated=set();epoch+=1;cursor=0;stats['recoveries']+=1
  if accept:active=d.copy();beat=0;phase='response';stats['dummy_requested']+=1
  elif o['response_valid']and x['rr']:
   stats['read_beats'if active['read']else'write_responses']+=1
   if o['response_last']:phase='done'
   else:beat+=1
  elif o['done_valid']and done_ready:phase='idle';active=None;stats['dummy_done']+=1
  return o
 emit(rstn=0);emit(rstn=0)
 if unit:
  for read,beats in [(1,0),(1,5),(0,2)]:emit(qv=1,qr=read,qb=beats)
  emit(qv=1,qb=1,qstatus=0)
  for n in [1,2,3,4,1]:
   rd=int(n!=1 or stats['dummy_requested']==0);emit(qv=1,qs=3,qp=3,qe=limit,qt=2047,qr=rd,qb=n)
   for b in range(n):
    for _ in range(7):emit(rr=0,qv=1,qt=0,qb=1)
    emit(rr=1)
   for _ in range(9):emit(dr=0,qv=1,qt=0,qb=1)
   emit(dr=1);emit()
  emit(qv=1,qb=4);emit(rr=1);emit(rstn=0);emit()
 else:
  for n in [1,2,3,4]:
   for slot in range(capacity):emit(tv=1,ts=slot,tp=slot%ports,tag=2047-slot,read=1 if slot%2==0 else 0,beats=n if slot%2==0 else 1)
   isolation_mask=full if n==4 else 1
   emit(iso=isolation_mask,cv=1,cs=0,rv=1)
   if is_switch:
    for slot in list(obligations):
     if not (isolation_mask>>obligations[slot]['port']&1):emit(cv=1,cs=slot)
   for _ in range(14):emit(rr=0,rv=1,cv=1,cs=0)
   while obligations or phase!='idle':emit(rr=int(len(rows)%3!=0),rv=1,cv=int(len(rows)%4==0),cs=0)
   emit(rv=1,quiet=0);emit(rv=1,up=0);emit(rv=1,init=0);emit(rv=1,drop=full);emit(rv=1,re=epoch);emit(rv=1)
   emit(cv=1,cs=0,ce=(epoch-1)&limit);emit(tv=1,ts=0,te=(epoch-1)&limit,read=1,beats=1)
  emit(rstn=0)
  while epoch<limit:emit(down=1);emit(rv=1)
  emit(down=1);emit(rv=1,re=0);emit(rv=1,re=limit);emit(rstn=0)
  # New traffic in isolation remains a real obligation even after the original trigger.
  emit(iso=full);emit(tv=1,ts=0,tp=ports-1,tag=1024,read=1,beats=4);emit();emit(rr=1);emit(rstn=0)
 for cycle in range(900):
  if cycle in [287,593]:emit(rstn=0);continue
  if unit:emit(qv=rng.randrange(2),qs=rng.randrange(4),qp=rng.randrange(4),qe=rng.randrange(limit+1),qt=rng.randrange(2048),qr=rng.randrange(2),qb=rng.randrange(6),qstatus=8 if rng.randrange(4)else 0,rr=rng.randrange(2),dr=rng.randrange(2))
  else:
   kind=rng.randrange(10);kw={}
   if kind<4:kw=dict(tv=1,ts=rng.randrange(4),tp=rng.randrange(ports),tag=rng.randrange(2048),read=1,beats=rng.randrange(1,5),te=epoch if rng.randrange(5)else(epoch+1)&limit)
   elif kind==4:kw=dict(iso=1<<rng.randrange(ports))
   elif kind==5:kw=dict(cv=1,cs=rng.randrange(4),ce=epoch if rng.randrange(5)else(epoch+1)&limit)
   elif kind==6:kw=dict(rv=1,quiet=rng.randrange(2),re=rng.randrange(limit+1))
   elif kind==7:kw=dict(up=rng.randrange(full+1),init=rng.randrange(full+1),drop=rng.randrange(full+1))
   emit(rr=rng.randrange(2),**kw)
 emit(rstn=0);emit()
 path.write_text(''.join(' '.join(format(int(v),'x')for v in row)+'\n'for row in rows))
 return {'rows':len(rows),'events':stats,'seed':8031+ports*103+capacity*17+is_switch+unit*91}

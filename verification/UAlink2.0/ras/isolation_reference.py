"""Independent obligation dictionary and explicit epoch authority; no RTL imports."""
import random

def generate(path,ports,capacity,is_switch,epoch_width=2):
 rng=random.Random(0x1907+ports*17+capacity*3+is_switch);slots={};isolated=set();epoch=0;rr=0;held=None;rows=[];stats={'track':0,'normal_done':0,'dummy_requests':0,'dummy_done':0,'discarded':0,'recoveries':0,'wrap_rejects':0}
 full=(1<<ports)-1;max_epoch=(1<<epoch_width)-1
 def emit(reset=1,iso=0,down=0,up=None,init=None,drop=0,quiet=1,tv=0,ts=0,te=None,tp=0,tag=0,read=1,beats=1,cv=0,cs=0,ce=None,dr=0,dv=0,ds=0,de=None,rv=0,re=None):
  nonlocal slots,isolated,epoch,rr,held
  up=full if up is None else up;init=full if init is None else init;te=epoch if te is None else te;ce=epoch if ce is None else ce;de=epoch if de is None else de;re=epoch+1 if re is None else re
  re&=max_epoch;trigger={p for p in range(ports) if (iso|down)>>p&1}
  if trigger and not is_switch:trigger=set(range(ports))
  current=isolated|trigger
  mask=sum(1<<p for p in current) if reset else 0
  forward=(up&init&~drop&~mask&full) if reset else 0
  legal_track=ts<capacity and ts not in slots and te==epoch and tp<ports and 1<=beats<=4 and (read or beats==1)
  tr=int(reset and legal_track)
  actual_c=cv and cs in slots and ce==epoch
  normal=bool(reset and actual_c and slots[cs]['port'] not in current and not slots[cs]['issued'])
  discard=bool(reset and cv and not normal)
  chosen=held if held is not None else next((s for s in [(rr+n)%capacity for n in range(capacity)] if s in slots and slots[s]['port'] in current and not slots[s]['issued']),None)
  qv=int(reset and chosen is not None);q=slots[chosen] if qv else {'port':0,'tag':0,'read':0,'beats':0}
  done=bool(reset and dv and ds in slots and de==epoch and slots[ds]['issued'] and slots[ds]['port'] in current)
  recover=bool(reset and isolated and not slots and quiet and up==full and init==full and not drop and not trigger and not tv and not cv and not dv and epoch<max_epoch and re==epoch+1)
  errors=int(reset and tv and not legal_track)|(int(reset and cv and not actual_c)<<1)|(int(reset and dv and not done)<<2)|(int(reset and rv and not recover)<<3)
  out=[mask,forward,epoch,len(slots),tr,int(reset),discard,qv,chosen if qv else 0,epoch if qv else 0,q['port'],q['tag'],q['read'],q['beats'],8 if qv else 0,int(reset),recover,int(rv and recover),errors]
  values=[reset,iso,down,up,init,drop,quiet,tv,ts,te,tp,tag,read,beats,cv,cs,ce,dr,dv,ds,de,rv,re]+out;rows.append(values)
  if not reset:slots={};isolated=set();epoch=0;rr=0;held=None;return out
  isolated=current
  if tv and tr:slots[ts]={'port':tp,'tag':tag,'read':read,'beats':beats,'issued':False};stats['track']+=1
  if normal:del slots[cs];stats['normal_done']+=1
  if qv and dr:slots[chosen]['issued']=True;rr=(chosen+1)%capacity;held=None;stats['dummy_requests']+=1
  elif qv:held=chosen
  if done:del slots[ds];stats['dummy_done']+=1
  if discard:stats['discarded']+=1
  if rv and recover:epoch+=1;isolated=set();rr=0;stats['recoveries']+=1
  if rv and epoch==max_epoch and not recover:stats['wrap_rejects']+=1
  return out
 emit(reset=0);emit(reset=0)
 if capacity>1:
  emit(tv=1,ts=capacity-1,tag=1900,read=1,beats=4);emit(iso=1)
  emit(tv=1,ts=0,tag=1800,read=0,beats=1)
  for _ in range(3):emit(dr=0)
  emit(dr=1);emit(dv=1,ds=capacity-1);emit(dr=1);emit(dv=1,ds=0);emit(reset=0)
 # Same-edge isolation beats real completion, request backpressure cannot cancel obligations.
 for s in range(capacity):emit(tv=1,ts=s,tp=s%ports,tag=1024+s,read=s%2,beats=4 if s%2 else 1)
 emit(iso=1,cv=1,cs=0,dr=0)
 for _ in range(4):emit(iso=1,rv=1,dr=0)
 # Non-Switch scope flushes all; Switch unaffected ports still complete normally.
 if is_switch:
  for s in list(slots):
   if slots[s]['port']!=0:emit(cv=1,cs=s)
 while slots:
  out=emit(dr=1);chosen=out[8]
  emit(cv=1,cs=chosen,rv=1)  # late response after dummy issuance must not free it
  emit(dv=1,ds=chosen,de=(epoch+1)&max_epoch)  # stale/future completion rejected
  emit(dv=1,ds=chosen)
 emit(rv=1,quiet=0);emit(rv=1,up=0);emit(rv=1,init=0);emit(rv=1,drop=full);emit(rv=1,re=epoch);emit(rv=1)
 emit(tv=1,ts=0,te=0,tag=2047);emit(cv=1,cs=0,ce=0);emit(dv=1,ds=0,de=0)
 # New requests arriving while isolated still acquire a real dummy obligation.
 emit(down=1);emit(tv=1,ts=0,tp=0,tag=2047,read=1,beats=4)
 emit(dv=1,ds=0)  # done before request handshake is not completion
 emit(dr=1)
 for _ in range(6):emit(rv=1,cv=1,cs=0)
 emit(dv=1,ds=0);emit(dv=1,ds=0);emit(rv=1)
 # Reach maximum epoch and prove wrap fails closed without silently clearing isolation.
 while epoch<max_epoch:emit(iso=1);emit(rv=1)
 emit(iso=1);emit(rv=1,re=0);emit(rv=1,re=max_epoch);emit(reset=0)
 # Random adversarial events with independent legal completions and qualification changes.
 for cycle in range(1100):
  if cycle in [399,799]:emit(reset=0);continue
  choice=rng.randrange(12);kw={}
  if choice<4:
   kw={'tv':1,'ts':rng.randrange(4),'tp':rng.randrange(4),'tag':rng.randrange(2048),'read':rng.randrange(2),'beats':rng.randrange(6),'te':epoch if rng.randrange(4) else (epoch+1)&max_epoch}
  elif choice==4:kw={'iso':1<<rng.randrange(ports)}
  elif choice==5:kw={'down':1<<rng.randrange(ports)}
  elif choice==6:kw={'cv':1,'cs':rng.randrange(4),'ce':epoch if rng.randrange(4) else (epoch+1)&max_epoch}
  elif choice==7:kw={'dv':1,'ds':rng.randrange(4),'de':epoch if rng.randrange(4) else (epoch+1)&max_epoch}
  elif choice==8:kw={'rv':1,'quiet':rng.randrange(2),'re':rng.randrange(max_epoch+1)}
  elif choice==9:kw={'up':rng.randrange(full+1),'init':rng.randrange(full+1),'drop':rng.randrange(full+1)}
  kw['dr']=rng.randrange(2);emit(**kw)
 emit(reset=0);emit()
 path.write_text(''.join(' '.join(format(int(x),'x') for x in row)+'\n' for row in rows))
 return {'rows':len(rows),'events':stats}

"""Independent normal-burst queue observer; inputs are native events, not DUT state."""
import random

def generate(path,ports):
 rng=random.Random(0x92527+ports);lines=[];pending={};sticky=0
 def emit(reset,known,slot,rv,rp,known_class,has_data,rvc,num,dv,dp,dvc,off,last):
  nonlocal sticky,pending
  e=0
  if reset and not sticky:
   if (rv and rp>=ports) or (dv and dp>=ports):e|=1
   if rv and not known_class:e|=256
   if pending and (not known or slot>=ports):e|=512
   for p in range(ports):
    req=rv and rp==p;data=dv and dp==p
    start=req and known_class and has_data and p not in pending
    due=p in pending and known and slot==p
    if start and not data:e|=2
    if data and p not in pending and not start:e|=4
    if req and known_class and has_data and p in pending:e|=8
    if due and not data:e|=16
    if data and (start or due):
     expected=pending[p][0] if due else (0,num==0,rvc)
     if off!=expected[0]:e|=32
     if last!=expected[1]:e|=64
     if dvc!=expected[2]:e|=128
  busy=sum(1<<p for p in pending)
  fields=[reset,known,slot,rv,rp,known_class,has_data,rvc,num,dv,dp,dvc,off,last,e,sticky,busy]
  lines.append(' '.join(format(int(x),'x') for x in fields))
  if not reset:pending={};sticky=0
  elif not sticky and not e:
   for p in range(ports):
    if p in pending and known and slot==p and dv and dp==p:
     pending[p].pop(0)
     if not pending[p]:del pending[p]
    elif rv and rp==p and known_class and has_data and num:
     pending[p]=[(k,k==num,rvc) for k in range(1,num+1)]
  if reset:sticky|=e
 def reset():emit(0,0,0,0,0,1,0,0,0,0,0,0,0,0)
 reset();reset()
 # Start at every legal first port with each length, arbitrary VC, independent per-port tails.
 for length in range(4):
  for first in range(ports):
   reset();emit(1,0,0,1,first,1,1,3,length,1,first,3,0,length==0)
   for n in range(1,ports*4+1):
    p=(first+n)%ports
    if p in pending:
     off,last,vc=pending[p][0];emit(1,1,p,1,p,1,0,(vc+1)%4,3,1,p,vc,off,last)
    else:emit(1,1,p,0,3,1,0,3,3,0,3,3,3,1)
 # Thousands of healthy slots, including all ports concurrently owning burst tails.
 reset()
 for n in range(2400):
  p=n%ports
  if p in pending:
   off,last,vc=pending[p][0];emit(1,1,p,rng.randrange(2),p,1,0,rng.randrange(4),rng.randrange(4),1,p,vc,off,last)
  elif rng.randrange(4):
   vc=rng.randrange(4);length=rng.randrange(4);has=rng.randrange(4)!=0
   emit(1,1,p,1,p,1,has,vc,length,has,p,vc,0,length==0)
  else:emit(1,1,p,0,3,0,1,3,3,0,3,3,3,1)
 # Explicit errors each start with a fresh epoch; retain frozen state and sticky under followup noise.
 faults=['first','first_offset','first_last','first_vc','orphan','overlap','gap','read_gap','offset','last','final_last','vc','unknown','phase']+(['port','data_port'] if ports<4 else [])+(['pair_port'] if ports>1 else [])
 for fault in faults:
  reset()
  if fault in ['overlap','gap','read_gap','offset','last','final_last','vc','phase']:
   emit(1,0,0,1,0,1,1,2,3,1,0,2,0,0)
  args=[1,1,0,0,0,1,0,2,3,1,0,2,1,0]
  if fault=='first':args=[1,0,0,1,0,1,1,2,3,0,0,2,0,0]
  if fault in ['first_offset','first_last','first_vc','pair_port']:
   args=[1,0,0,1,0,1,1,2,0,1,0,2,0,1]
   if fault=='first_offset':args[12]=1
   if fault=='first_last':args[13]=0
   if fault=='first_vc':args[11]=1
   if fault=='pair_port':args[10]=1
  if fault=='orphan':args=[1,1,0,0,0,1,0,2,0,1,0,2,0,1]
  if fault=='overlap':args[3]=1;args[6]=1
  if fault=='gap':args[9]=0
  if fault=='read_gap':args[3]=1;args[9]=0
  if fault=='final_last':
   emit(1,1,0,0,0,1,0,2,3,1,0,2,1,0)
   emit(1,1,0,0,0,1,0,2,3,1,0,2,2,0)
   args[12]=3;args[13]=0
  if fault=='offset':args[12]=2
  if fault=='last':args[13]=1
  if fault=='vc':args[11]=1
  if fault=='unknown':args[3]=1;args[5]=0
  if fault=='phase':args[1]=0
  if fault=='port':args[9]=0;args[3]=1;args[4]=ports
  if fault=='data_port':args[10]=ports
  emit(*args)
  for _ in range(3):emit(1,1,0,1,0,1,1,0,0,1,0,0,0,1)
 reset();emit(1,0,0,1,0,1,1,0,0,1,0,0,0,1)
 path.write_text('\n'.join(lines)+'\n')
 return {'rows':len(lines),'error_scenarios':faults}

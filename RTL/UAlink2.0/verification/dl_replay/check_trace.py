"""Verify every actual peer cycle and the actual-output feedback transport independently.
Run: python3 verification/dl_replay/check_trace.py --record peer_CASE.json
Output: trace_check_CASE.json; rejects model/output differences or fabricated/misrouted link input.
Next: all actual cases, directed negatives and exact source/tool identities are required for freezing.
"""
from pathlib import Path
import argparse,json,sys,collections,hashlib
R=Path(__file__).resolve().parents[2];D=R;S=R/'build/verification/dl_replay';sys.path[:0]=[str(D),str(D/'verification/peer')]
from cycle_reference import CycleReference
p=argparse.ArgumentParser();p.add_argument('--record',required=True);a=p.parse_args();r=json.loads((S/a.record).read_text());b=R/r['directory'];pp=json.loads((D/'config/dl_replay/ports.json').read_text());sp=json.loads((D/'config/dl_replay/storage_ports.json').read_text());layout=json.loads((D/'config/dl_replay/trace_layout.json').read_text());names=layout['fields'];oracles=[CycleReference(r['depth'],r['width'],pp,sp) for _ in range(2)];queues=[collections.deque(),collections.deque()];reservations=[0,0];sent=received=0;count=0
app=[collections.deque(),collections.deque()];request_groups=[collections.Counter(),collections.Counter()];counts={n:[0,0] for n in ('accepted','delivered','slots','replays','requests','physical_wraps','full_nops','crc_bad','lost_group_flits','lost_requests','receive_discards')}
validation=json.loads((R/'config/dl_replay/reference_qualification.json').read_text())
if validation['source_sha256']!=hashlib.sha256((D/'verification/peer/cycle_reference.py').read_bytes()).hexdigest() or validation['rows']!=121944:raise ValueError('full prior-vector reference qualification required')
def inputs(packed):
 out={};shift=0
 for n,w in pp['inputs'][1:]:
  if w=='W':continue
  out[n]=(packed>>shift)&((1<<w)-1);shift+=w
 return out
def error(*x):raise ValueError(x)
wire=iter((b/'wire_trace.txt').open());pending=next(wire,None)
with (b/'trace.txt').open() as trace:
 while True:
  first=trace.readline()
  if not first:break
  rows=[]
  for side,line in enumerate((first,trace.readline())):
   if not line:error('missing second actual RTL cycle')
   fields=line.split();tick,who=map(int,fields[:2]);actual=[int(x,16) for x in fields[2:]]
   if tick!=count or who!=side or len(actual)!=len(names):error('exact tick/side/complete fields',tick,side)
   i=inputs(actual[0]);expected_in=None
   if queues[side] and queues[side][0]['due']<=tick:expected_in=queues[side].popleft()
   if i['i_rx_event_valid']!=int(expected_in is not None):error('actual link event identity',tick,side)
   if expected_in:
    received+=1
    if (i['i_rx_header'],actual[2],i['i_rx_crc_ok'],i['i_rx_event_discard'])!=(expected_in['header'],expected_in['data'],expected_in['crc'],expected_in['discard']):error('fabricated or changed feedback',tick,side)
   expected=oracles[side].cycle(*actual[:3])
   if actual!=expected:error('independent complete cycle',tick,side,[(names[j],x,y) for j,(x,y) in enumerate(zip(actual,expected)) if x!=y][:5])
   rows.append((i,dict(zip(names,actual))))
  for side,(i,values) in enumerate(rows):
   if values['o_rx_payload_accept_pre']:
    source=1-side
    if not app[source] or app[source].popleft()!=values['rx_data_pre']:error('independent application order/data',count,side)
    counts['delivered'][source]+=1
  for side,(i,values) in enumerate(rows):
   if values['o_payload_accept_pre']:
    app[side].append(values['data']);counts['accepted'][side]+=1
    counts['physical_wraps'][side]+=int(values['o_ctl_write_pointer_post']==0)
   counts['full_nops'][side]+=int(bool(i['i_flit_request'] and i['i_payload'] and not values['o_issue_payload_pre']))
   if not values['o_out_valid_post']:continue
   if pending is None:error('missing actual outgoing frame')
   x=pending.split();wt,ws,due,group,action,crc,discard=map(int,x[:7]);header,data=[int(y,16) for y in x[7:]]
   if (wt,ws,due,group)!=(count,side,count+r['delay'],reservations[side]//r['group_size']):error('actual outgoing slot or due/group mismatch',count,side)
   reservations[side]+=1;sent+=1;counts['slots'][side]+=1;counts['replays'][side]+=values['o_out_replay_post']
   if ((values['o_out_header_post']>>21)&7)==3:
    counts['requests'][side]+=1;request_groups[side][group]+=1
    if request_groups[side][group]>1:error('independent actual-group request limit',count,side)
   action_counter={1:'lost_group_flits',2:'lost_requests',3:'crc_bad',4:'receive_discards'}
   if action in action_counter:counts[action_counter[action]][side]+=1
   if action not in (0,1,2,3,4) or (not r['inject'] and action!=0):error('undeclared fault action')
   if header!=(values['o_out_header_post']^(0x100 if action==3 else 0)) or data!=values['out_data_post']:error('wire did not carry actual DUT header/data')
   if crc!=int(action!=3) or discard!=int(action==4):error('declared CRC/discard action')
   if action==1 and group!=10:error('declared whole-group erasure')
   if action==2 and ((values['o_out_header_post']>>21)&7)!=3:error('declared request copy loss')
   if action not in (1,2):queues[1-side].append(dict(due=due,header=header,data=data,crc=crc,discard=discard))
   pending=next(wire,None)
  count+=1
if pending is not None:error('extra fabricated output in link trace')
if r['run_exit']!=0 or count!=r['stats']['ticks'] or sent!=sum(r['stats']['slots']):error('complete terminal actual execution required')
if any(app) or counts['accepted']!=[r['count']]*2 or counts['delivered']!=[r['count']]*2:error('independent complete application delivery')
if counts!={n:r['stats'][n] for n in counts} or r['stats']['clock_edges']!=2*(count+1):error('actual counters must match complete traces')
result=dict(independent_counters=counts,record=a.record,ticks=count,cycle_rows=count*2,actual_sent_frames=sent,actual_received_frames=received,all_public_ports_and_state=True,actual_output_feedback_audited=True,reference_sha256=validation['source_sha256'],trace_sha256=hashlib.sha256((b/'trace.txt').read_bytes()).hexdigest(),wire_trace_sha256=hashlib.sha256((b/'wire_trace.txt').read_bytes()).hexdigest());out=S/('trace_check_'+Path(a.record).stem+'.json');out.write_text(json.dumps(result,indent=2)+'\n');print('PASS',count*2,'complete actual RTL cycles;',sent,'actual feedback frames')

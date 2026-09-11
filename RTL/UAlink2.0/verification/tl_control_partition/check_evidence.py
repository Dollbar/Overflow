"""Run: python3 [-O] verification/tl_control_partition/check_evidence.py.
Audit independent Request/Response sources against actual wire classes and SRAM words.
Outputs evidence.json; blocked-class completion is explicitly not claimed.
"""
from pathlib import Path
from collections import deque
import argparse,hashlib,json,re,sys
R=Path(__file__).resolve().parents[2];S=R/'build/verification/tl_control_partition';sys.path.insert(0,str(R/'model/tl'))
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--peers-label',default='peers_semantics');p.add_argument('--minimum-label',default='minimum_semantics');p.add_argument('--peers-only',action='store_true');p.add_argument('--output-label');a=p.parse_args()
for label in (a.peers_label,a.minimum_label,a.output_label):
    if label is not None and not re.fullmatch(r'[a-zA-Z0-9_-]+',label):p.error('labels must be single directory/file names')
if a.peers_only and not a.output_label:p.error('--peers-only requires a distinct --output-label')
if not a.peers_only and (a.peers_label!='peers_semantics' or a.minimum_label!='minimum_semantics' or a.output_label):p.error('custom labels require --peers-only; full original stage gates are separate')
from credit_context import Context,decode_context
from receive_context import ReceiveContext
from credit_admission import requirements
classes={'CONTROL':0,'DATA':1,'BYTE_ENABLE':2,'NOP':3,'MESSAGE':4,'POISON':5,'AUTH':6,'RESET':7}
def need(ok,msg):
    if not ok:raise ValueError(msg)
def read(p):return json.loads(p.read_text())
def identity(r):
    for name,digest in r['sources'].items():need(hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest,'compiled source identity '+name)
def pack(v,b):return sum(int(x)<<(j*b) for j,x in enumerate(v))
def unpack(v,b):return [(v>>(j*b))&((1<<b)-1) for j in range(20)]
reports={}
for mode,blocked in ((a.peers_label,-1),(a.minimum_label,-1)):
    result=read(S/mode/'results.json');identity(result);need(result['complete'] and len(result['results'])==16,'actual mode denominator '+mode)
    total=dict(cycles=0,headers=[0,0],data_halves=[0,0],stored=0,fc=0,cross_tail=0,held_edges=0,cmd_returns=0,data_returns=0)
    for case in result['results']:
        b=S/mode/f'w{case["width"]}_a{case["auth"]}_s{case["shared"]}_l{case["delay"]}';m=re.search(r'PASS actual channels .* cycles=(\d+) stored=(\d+) fc=(\d+) cross_tail=(\d+)',(b/'run.log').read_text());need(case['compile_exit']==case['run_exit']==0 and m,'real pass log')
        headers=[[[int(x,16) for x in (b/f'headers{e}{c}.hex').read_text().splitlines()] for c in (0,1)] for e in (0,1)];data=[[[int(x,16) for x in (b/f'data{e}{c}.hex').read_text().splitlines()] for c in (0,1)] for e in (0,1)]
        hi=[[0,0],[0,0]];di=[[0,0],[0,0]];txctx=[Context(auth=bool(case['auth'])) for _ in (0,1)];rxctx=[ReceiveContext(auth=bool(case['auth'])) for _ in (0,1)];queue=[deque(),deque()];returned=[[0]*20 for _ in (0,1)];published=[[0]*20 for _ in (0,1)];caps=[1]*20;history=[];completion=[0,0];counts=dict(stored=0,fc=0,cross_tail=0)
        for row,line in enumerate((b/'trace.txt').read_text().splitlines()):
            f=line.split();need(len(f)==25,'raw observation shape');v=[int(x) for x in f[:19]]+[int(x,16) for x in f[19:]]
            cycle,e,hreq,hrsp,dreq,drsp,pending,pv,taken,ht,dt,tt,ft,rxv,rxt,ret,count,tm,rm,tx,rx,word,av,cap,pub=v
            need(e==row%2 and [hreq,hrsp]==hi[e] and [dreq,drsp]==di[e],'class queue index continuity');need(pending==len(txctx[e].pending),'actual pending vs independent context');need(count==len(queue[e]),'actual SRAM count vs expected words')
            if blocked>=0:need(hi[e][blocked]==di[e][blocked]==0,'blocked source must never be acknowledged')
            need(not rxv or rxt,'no rejected inflight flit');need(not(ht or dt or tt or ft) or taken,'no speculative source consumption')
            if row>=2:
                old=history[row-2]
                if old[7] and not old[8]:need(pv and tx==old[19] and tm==old[17],'stable candidate under output stall');total['held_edges']+=1
            peer_row=row-2*case['delay']+(1 if e==0 else -1);expected=history[peer_row] if peer_row>=0 else None
            need(rxv==(expected[8] if expected else 0),'wire valid delay')
            if rxv:need(rx==expected[19] and rm==expected[17],'wire payload delay')
            if ret:
                need(queue[e] and word==queue[e].popleft(),'exact actual 600-bit SRAM retirement');returned[e]=[a+b for a,b in zip(returned[e],unpack(word>>520,4))];counts['stored']+=1
            if rxv:
                msg=tuple((rx>>(256*j))&255 if rm&(1<<j) else None for j in (0,1));ob=rxctx[e].step(rx&((1<<256)-1),msg=msg)
                if ob['store']:queue[e].append((pack(ob['releases'],4)<<520)|(pack([classes[x] for x in ob['classes']],3)<<514)|(rm<<512)|rx)
            if taken:
                msg=tuple((tx>>(256*j))&255 if tm&(1<<j) else None for j in (0,1));tokens=list(txctx[e].pending);newclass=None;nh=0;nt=0;nd=[0,0];oldclass=int(tokens[0].slot>=15) if tokens else None
                if pending<=1 and msg[0] is None:
                    dec,append,_=decode_context(tx&((1<<256)-1));tokens.extend(append)
                    if dec['fields']:
                        roles={int(r['kind'] not in (1,3)) for r in dec['records']};need(len(roles)==1,'prepared Control cannot mix class sources');newclass=roles.pop();nh=1<<newclass
                        need(hi[e][newclass]<len(headers[e][newclass]) and tx&((1<<256)-1)==headers[e][newclass][hi[e][newclass]],'actual selected header order/class')
                        need(all(n<=a for n,a in zip(requirements(tx&((1<<256)-1),shared=bool(case['shared'])),unpack(av,case['width']+1))),'full new-header credit funding')
                ob=txctx[e].step(tx&((1<<256)-1),msg=msg)
                for j,k in enumerate(ob['classes']):
                    half=(tx>>(256*j))&((1<<256)-1)
                    if k in ('DATA','BYTE_ENABLE'):
                        token=tokens.pop(0);owner=int(token.slot>=15);index=di[e][owner]+nd[owner];need(index<len(data[e][owner]) and half==data[e][owner][index],'actual Data/BE from correct independent owner');nd[owner]+=1
                    if k=='AUTH':need(newclass is not None and half==(int((b/f'tags{e}{newclass}.hex').read_text().splitlines()[hi[e][newclass]],16) if case.get('tag_pattern') else 0),'supplied tag fixture follows header');nt=1<<newclass
                need((ht,dt,tt)==(nh,pack(nd,2),nt),'source acknowledgements match independent wire interpretation')
                if newclass is not None:hi[e][newclass]+=1
                for c in (0,1):di[e][c]+=nd[c]
                if pending==1 and newclass is not None and newclass!=oldclass:counts['cross_tail']+=1
            if ft:
                counts['fc']+=1
                if tm==2:
                    need(tx==((1|(case['shared']<<8))<<256) and published[e]==caps,'actual initial credit/complete order');completion[e]+=1
                else:
                    low=tx&((1<<256)-1);need(tm==0 and 0<low<(1<<28),'actual FC field')
                    for group,(pos,nbits) in enumerate(((22,3),(16,3),(8,5),(0,5))):
                        value=(low>>pos)&((1<<(nbits+3))-1);lane=1+((value>>nbits)&3) if value&(1<<(nbits+2)) else 0;slot=group*5+lane;published[e][slot]+=value&((1<<nbits)-1);need(published[e][slot]<=caps[slot]+returned[e][slot],'no credit return before actual FIFO consumption')
            history.append(v)
        need(completion==[1,1] and list(counts.values())==[int(x) for x in m.groups()[1:]],'raw terminal event counts')
        for e in (0,1):
            need(not queue[e] and not txctx[e].pending and not rxctx[e].pending,'all sent tenure and SRAM words drained')
            need(published[e]==[a+b for a,b in zip(caps,returned[e])],'actual final logical credit conservation')
            for c in (0,1):
                need([hi[e][c],di[e][c]]==([0,0] if c==blocked else [len(headers[e][c]),len(data[e][c])]),'eligible class completes; blocked class unchanged')
                total['headers'][c]+=hi[e][c];total['data_halves'][c]+=di[e][c]
            total['cmd_returns']+=sum(returned[e][:10]);total['data_returns']+=sum(returned[e][10:])
        if not case['auth'] and blocked==-1:need(counts['cross_tail']>0,'real cross-class swapped tail exercised')
        else:need(counts['cross_tail']==0,'no Auth or blocked-class coalescing')
        for k,x in counts.items():total[k]+=x
        total['cycles']+=int(m[1])
    reports[mode]=total
queue_reports={}
for mode in reports:
    totals=dict(enqueued_headers=0,enqueued_data=0,header_backpressure=0,data_backpressure=0)
    for case in read(S/mode/'results.json')['results']:
        b=S/mode/f'w{case["width"]}_a{case["auth"]}_s{case["shared"]}_l{case["delay"]}'
        enq=[[[0,0] for c in (0,1)] for e in (0,1)];deq=[[[0,0] for c in (0,1)] for e in (0,1)]
        wire_rows=[line.split() for line in (b/'trace.txt').read_text().splitlines()]
        queue_rows=(b/'queue_trace.txt').read_text().splitlines();need(len(queue_rows)==2*len(wire_rows),'queue/wire trace denominator')
        for row,line in enumerate(queue_rows):
            cycle,e,c,wh,wd,hi,di,hv,hr,dv,dr,ht,dt,hcount,dcount,da=map(int,line.split())
            need(e==row%4//2 and c==row%2,'queue trace ordering')
            wire=[int(x) for x in wire_rows[row//2][:19]];need([cycle,e,hi,di,ht,dt]==[wire[0],wire[1],wire[2+c],wire[4+c],(wire[9]>>c)&1,(wire[10]>>(2*c))&3],'queue events agree with actual wire observer')
            need([wh,wd]==enq[e][c] and [hi,di]==deq[e][c],'producer/consumer index continuity')
            need([hcount,dcount]==[wh-hi,wd-di],'actual queued conservation before every edge')
            need(0<=hcount<=case['header_depth'] and 0<=dcount<=2*case['bank_depth'],'exact Tx bounds include read latency')
            need(ht<=hcount and dt<=dcount,'no consumption of unqueued input');need(da==(min(dv,2*case['bank_depth']-dcount) if dv in (1,2) else 0),'actual partial input acceptance')
            if case['blocked']==c:need(hi==di==ht==dt==0,'blocked queue never loses contents')
            enq[e][c][0]+=hv*hr;enq[e][c][1]+=da;deq[e][c][0]+=ht;deq[e][c][1]+=dt
            totals['enqueued_headers']+=hv*hr;totals['enqueued_data']+=da
            totals['header_backpressure']+=int(hv and not hr);totals['data_backpressure']+=int(dv and not dr)
        for e in (0,1):
            for c in (0,1):
                if case['blocked']!=c:need(enq[e][c]==deq[e][c],'eligible queues completely drained')
                else:need(enq[e][c]==[case['header_depth'],2*case['bank_depth']],'blocked queues retain full bounded backlog')
    need(totals['header_backpressure']>0 and totals['data_backpressure']>0,'actual independent backpressure')
    queue_reports[mode]=totals
partition_reports={}
for mode in reports:
    counters=dict(source_groups=0,partitions=0,fields=0,split_groups=0,stalled_edges=0)
    for case in read(S/mode/'results.json')['results']:
        b=S/mode/f'w{case["width"]}_a{case["auth"]}_s{case["shared"]}_l{case["delay"]}'
        sources=[[[int(x,16) for x in (b/f'sources{e}{c}.hex').read_text().splitlines()] for c in (0,1)] for e in (0,1)]
        tags=[[[int(x,16) for x in (b/f'source_tags{e}{c}.hex').read_text().splitlines()] for c in (0,1)] for e in (0,1)]
        groups=[[0,0],[0,0]];enqueued=[[0,0],[0,0]];consumed_fields=[[0,0],[0,0]];group_parts=[[0,0],[0,0]];last_cursor=[[0,0],[0,0]];last_output=[[None,None],[None,None]]
        qs=[list(map(int,x.split())) for x in (b/'queue_trace.txt').read_text().splitlines()];ps=(b/'partition_trace.txt').read_text().splitlines();need(len(ps)==len(qs),'partition/queue trace denominator')
        for row,line in enumerate(ps):
            f=line.split();cycle,e,c,source_index,header_index,cursor,end,nfields,sv,taken,source_taken=map(int,f[:11]);word,tagword=map(lambda x:int(x,16),f[11:]);q=qs[row]
            need([cycle,e,c,header_index,taken]==[q[0],q[1],q[2],q[3],q[7]*q[8]],'partition enqueue agrees with actual FIFO event')
            need([source_index,header_index,cursor]==[groups[e][c],enqueued[e][c],last_cursor[e][c]],'source batch and cursor continuity')
            held=last_output[e][c]
            if held is not None:need([word,tagword,end,nfields]==held,'stable partition under FIFO stall');counters['stalled_edges']+=1
            last_output[e][c]=[word,tagword,end,nfields] if q[7] and not taken else None
            if not taken:need(not source_taken,'source never released without an enqueue');continue
            source=sources[e][c][source_index];original=decode_context(source)[0]['records'];actual=decode_context(word)[0]['records'];sizes={1:128,2:64,3:64,4:32,5:32};offset=consumed_fields[e][c]
            need(len(actual)==nfields>0 and (not case['auth'] or nfields<=4),'actual whole fields and Auth limit')
            need(word==source&(((1<<(32*end))-1)^((1<<(32*cursor))-1)),'original sector positions and exact bits retained')
            for j,record in enumerate(actual):
                expected=original[offset+j];need(record['sector']==expected['sector'] and record['kind']==expected['kind'],'no split or reordered individual field')
                mask=(1<<sizes[record['kind']])-1;need((word>>(32*record['sector']))&mask==(source>>(32*expected['sector']))&mask,'all transaction bits including Offset/Last unchanged')
            wanttags=(tags[e][c][source_index]>>(64*offset))&((1<<(64*nfields))-1) if case['auth'] else 0;need(tagword==wanttags,'exact corresponding source tags with zero unused slots')
            physical=[1]*20
            if case['shared']:physical[10]=2;physical[15]=0
            need(all(n<=cap for n,cap in zip(requirements(word,shared=bool(case['shared'])),physical)),'actual partition fits initialized capacity')
            consumed_fields[e][c]+=nfields;enqueued[e][c]+=1;group_parts[e][c]+=1;counters['fields']+=nfields;counters['partitions']+=1
            need(bool(source_taken)==(consumed_fields[e][c]==len(original)),'source ack only after every original field enqueued')
            if source_taken:
                need(end==8,'final source partition reaches full boundary');groups[e][c]+=1;counters['source_groups']+=1;counters['split_groups']+=int(group_parts[e][c]>1);group_parts[e][c]=0;consumed_fields[e][c]=0;last_cursor[e][c]=0
            else:last_cursor[e][c]=end
        for e in (0,1):
            for c in (0,1):need(groups[e][c]==len(sources[e][c]) and consumed_fields[e][c]==0,'every original source group completed')
    need(counters['split_groups']>0 and counters['stalled_edges']>0,'real split and source-stall coverage')
    partition_reports[mode]=counters
    completions=0
    for case in read(S/mode/'results.json')['results']:
        b=S/mode/f'w{case["width"]}_a{case["auth"]}_s{case["shared"]}_l{case["delay"]}';pending_replies={};closed=set()
        for line in (b/'trace.txt').read_text().splitlines():
            f=line.split();e=int(f[1]);taken=int(f[8]);ht=int(f[9]);tx=int(f[19],16)
            if not taken or not (ht&2):continue
            for record in decode_context(tx&((1<<256)-1))[0]['records']:
                word=tx>>(32*record['sector']);kind=record['kind'];need(kind in (2,4),'single-beat read response fixture type')
                if kind==2:
                    need((word>>37)&1 and ((word>>44)&3)==0,'uncompressed single-beat read mode');tag=(word>>47)&2047;offset=(word>>42)&3;last=(word>>36)&1;vc=(word>>58)&3;dest=(word>>16)&1023
                else:tag=(word>>15)&2047;offset=(word>>2)&3;last=(word>>1)&1;vc=(word>>26)&3;dest=(word>>4)&1023
                key=(e,tag);need(key not in closed,'no extra response after Last');state=pending_replies.setdefault(key,dict(offsets=[],vc=vc,dest=dest));need((state['vc'],state['dest'])==(vc,dest),'one reply preserves VC and destination');need(offset not in state['offsets'],'each response data Beat exactly once');state['offsets'].append(offset)
                if last:
                    need(state['offsets']==list(range(len(state['offsets']))),'complete ascending fixture offsets at Last');del pending_replies[key];closed.add(key);completions+=1
        need(not pending_replies and len(closed)==72,'both endpoints finish 36 read replies each')
    counters['completed_single_beat_read_replies']=completions

if a.peers_only:
    out=dict(actual_configs=32,modes=reports,queues=queue_reports,partitioning=partition_reports,scope='actual_peer_traces_only',unit_and_fault_gates_included=False,process_sta=False,full_goal_complete=False)
    (S/(a.output_label+'.json')).write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2));raise SystemExit(0)
checks=read(S/'checks/results.json');identity(checks);need(checks['complete'],'all external checks completed')
for kind,n in (('lint',2),('synthesis',2),('unit_fault',8),('peer_fault',56)):
    need(sum(x['kind']==kind for x in checks['results'])==n,'actual external check denominator '+kind)
for row in checks['results']:
    need(row['passed'],'external failure')
    if row['kind']=='unit_fault':
        d=S/('fault_'+row['name']);result=read(d/'results.json');identity(result);need(len(result['results'])==2,'two-width unit mutation denominator')
        for case in result['results']:need(case['compile_exit']==0 and case['run_exit']==1 and 'FATAL:' in (d/f'w{case["width"]}'/'run.log').read_text(),'real unit mutation')
    if row['kind']=='peer_fault':need('FATAL:' in (S/'checks'/(row['name']+'_'+row['config']+'.log')).read_text(),'real peer mutation')
unit=read(S/'unit/results.json');identity(unit);need(unit['complete'] and len(unit['results'])==2 and all(x['vectors']==2428 and x['compile_exit']==x['run_exit']==0 for x in unit['results']),'healthy complete RTL vectors')
physical=[]
for w in (8,16):
    modules=read(S/'checks'/f'synth_{w}.json')['modules'];need(len(modules)==1,'flattened partition module only');name,m=next(iter(modules.items()));need('tl_control_partition' in name,'correct synthesized module')
    clk=m['ports']['i_clk']['bits'];ff=[x for x in m['cells'].values() if 'DFF' in x['type'] or 'LATCH' in x['type']]
    need(sum(len(x['connections']['Q']) for x in ff)==4 and all(x['type'].startswith('$_SDFF') and x['connections']['C']==clk for x in ff),'four cursor state bits on input clock with synchronous reset')
    physical.append(dict(width=w,cells=len(m['cells']),ff_bits=4))
gate=read(S/'skill_gate.json');need(gate['ok'] and gate['errors']==0,'authored artifact gate')
out=dict(actual_configs=32,unit_negative_runs=16,peer_negative_runs=56,synthesis=physical,skill_errors=0,skill_advisories=gate['warnings'],unit_vectors=4856,modes=reports,queues=queue_reports,partitioning=partition_reports,individual_transactions_unchanged=True,individual_oversized_completion=False,full_upli_formatter=False,full_protocol_induction=False,process_sta=False,full_goal_complete=False)
(S/'evidence.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))

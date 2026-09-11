"""Run: python3 [-O] verification/tl_tx_buffered/check_evidence.py.
Audit independent Request/Response sources against actual wire classes and SRAM words.
Outputs evidence.json; blocked-class completion is explicitly not claimed.
"""
from pathlib import Path
from collections import deque
import hashlib,json,re,sys
R=Path(__file__).resolve().parents[2];S=R/'build/verification/tl_tx_buffered';sys.path.insert(0,str(R/'model/tl'))
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
for mode,blocked in (('none_final',-1),('request_final',0),('response_final',1),('minimum_final',-1),('deeper_final',-1)):
    result=read(S/mode/'results.json');identity(result);need(result['complete'] and len(result['results'])==16,'actual mode denominator '+mode)
    total=dict(cycles=0,headers=[0,0],data_halves=[0,0],stored=0,fc=0,cross_tail=0,held_edges=0,cmd_returns=0,data_returns=0)
    for case in result['results']:
        b=S/mode/f'w{case["width"]}_a{case["auth"]}_s{case["shared"]}_l{case["delay"]}';m=re.search(r'PASS actual channels .* cycles=(\d+) stored=(\d+) fc=(\d+) cross_tail=(\d+)',(b/'run.log').read_text());need(case['compile_exit']==case['run_exit']==0 and m,'real pass log')
        headers=[[[int(x,16) for x in (b/f'headers{e}{c}.hex').read_text().splitlines()] for c in (0,1)] for e in (0,1)];data=[[[int(x,16) for x in (b/f'data{e}{c}.hex').read_text().splitlines()] for c in (0,1)] for e in (0,1)]
        hi=[[0,0],[0,0]];di=[[0,0],[0,0]];txctx=[Context(auth=bool(case['auth'])) for _ in (0,1)];rxctx=[ReceiveContext(auth=bool(case['auth'])) for _ in (0,1)];queue=[deque(),deque()];returned=[[0]*20 for _ in (0,1)];published=[[0]*20 for _ in (0,1)];caps=[2]*10+[1 if blocked==0 else 4]*5+[1 if blocked==1 else 4]*5;history=[];completion=[0,0];counts=dict(stored=0,fc=0,cross_tail=0)
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
                    if k=='AUTH':need(newclass is not None and half==(((e<<24)|(newclass<<16)|hi[e][newclass]) if case.get('tag_pattern') else 0),'supplied tag fixture follows header');nt=1<<newclass
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
checks=read(S/'checks_cover/results.json');identity(checks);need(checks['complete'],'all actual external checks completed')
for kind,n in (('lint',2),('synthesis',2),('fifo_fault',6),('peer_fault',40)):
    need(sum(x['kind']==kind for x in checks['results'])==n,'actual external check denominator '+kind)
for row in checks['results']:
    need(row['passed'],'external check failure')
    if row['kind']=='fifo_fault':
        d=S/('fault_cover_'+row['name']);result=read(d/'results.json');identity(result);need(len(result['results'])==6,'negative FIFO parameter denominator')
        for case in result['results']:need(case['compile_exit']==0 and case['run_exit']==1 and 'FATAL:' in (d/f'd{case["depth"]}'/'run.log').read_text(),'real FIFO mutation run')
    if row['kind']=='peer_fault':need('FATAL:' in (S/'checks_cover'/(row['name']+'_'+row['config']+'.log')).read_text(),'real peer mutation run')
fifo=read(S/'fifo_cover/results.json');identity(fifo);need(fifo['complete'] and [x['depth'] for x in fifo['results']]==[1,2,3,5,129,257],'healthy FIFO depth coverage')
for case in fifo['results']:need(case['compile_exit']==case['run_exit']==0 and 'PASS FIFO' in (S/'fifo_cover'/f'd{case["depth"]}'/'run.log').read_text(),'actual SRAM FIFO pass')
physical=[]
for w in (8,16):
    m=read(S/'checks_cover'/f'synth_{w}.json')['modules']['tl_tx_buffered'];clk=m['ports']['i_clk']['bits'];ff=[x for x in m['cells'].values() if 'DFF' in x['type'] or 'LATCH' in x['type']];mac=[x for x in m['cells'].values() if x['type'].startswith('KD28_SRAM')]
    need(len(mac)==64 and all('LATCH' not in x['type'] and 'ADFF' not in x['type'] and x['connections'].get('C')==clk for x in ff) and all(x['connections']['RCLK']==clk and x['connections']['WCLK']==clk for x in mac),'all FIFO and SRAM clocks share input; control reset is synchronous')
    physical.append(dict(width=w,cells=len(m['cells']),ff_bits=sum(len(x['connections']['Q']) for x in ff),sram_cells=len(mac)))
gate=read(S/'skill_gate.json');need(gate['ok'] and gate['errors']==0,'mandatory authored artifact gate')
out=dict(actual_configs=80,fifo_configs=6,fifo_negative_runs=36,peer_negative_runs=40,synthesis=physical,skill_errors=0,skill_advisories=gate['warnings'],modes=reports,queues=queue_reports,actual_tx_fifo_queues=True,oversized_transaction_completion=False,full_protocol_induction=False,online_capacity_induction=False,process_sta=False,full_goal_complete=False)
(S/'evidence.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))

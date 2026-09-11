"""Run: python3 [-O] verification/tl_tx_channels/check_evidence.py.
Audit independent Request/Response sources against actual wire classes and SRAM words.
Outputs evidence.json; blocked-class completion is explicitly not claimed.
"""
from pathlib import Path
from collections import deque
import hashlib,json,re,sys
R=Path(__file__).resolve().parents[2];S=R/'build/verification/tl_tx_channels';sys.path.insert(0,str(R/'model/tl'))
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
for mode,blocked in (('none',-1),('request',0),('response',1)):
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
                    if k=='AUTH':need(half==0 and newclass is not None,'supplied tag fixture follows header');nt=1<<newclass
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
checks=read(S/'checks/results.json');identity(checks);need(checks['complete'],'all external checks')
for kind,count in (('lint',2),('synthesis',2),('unit_fault',8),('peer_fault',64)):
    need(sum(x['kind']==kind for x in checks['results'])==count,'actual check denominator '+kind)
for row in checks['results']:
    need(row['passed'],'failed external check '+str(row))
    if row['kind']=='unit_fault':
        d=S/('fault_'+row['name']);r=read(d/'results.json');identity(r);need(len(r['results'])==2,'two-width negative denominator')
        for x in r['results']:need(x['compile_exit']==0 and x['run_exit']==1 and 'FATAL:' in (d/f'w{x["width"]}'/'run.log').read_text(),'actual unit negative')
    if row['kind']=='peer_fault':
        name=row['name']+'_'+row['mode']+'_'+row['config'];need('FATAL:' in (S/'checks'/(name+'.log')).read_text(),'actual peer negative')
unit=read(S/'unit_final/results.json');identity(unit);need(len(unit['results'])==2 and all(x['passed'] and x['vectors']==629 for x in unit['results']),'healthy complete vectors')
physical=[]
for w in (8,16):
    m=read(S/'checks'/f'synth_{w}.json')['modules']['tl_tx_channels'];clk=m['ports']['i_clk']['bits'];ff=0
    for c in m['cells'].values():
        if 'DFF' in c['type'] or 'LATCH' in c['type']:
            need(c['type'].startswith('$_SDFF') and c['connections']['C']==clk,'all state on input clock with synchronous reset');ff+=len(c['connections']['Q'])
    need(ff==8,'class arbiter and actual packer state count');physical.append(dict(width=w,cells=len(m['cells']),ff_bits=ff))
gate=read(S/'skill_gate.json');need(gate['ok'] and gate['errors']==0,'authored quality gate')
out=dict(unit_vectors=1258,unit_negative_runs=16,peer_negative_runs=64,synthesis=physical,skill_errors=0,skill_advisories=gate['warnings'],actual_configs=48,modes=reports,prepared_request_response_selection=True,actual_tx_fifo_queues=False,oversized_transaction_completion=False,full_protocol_induction=False,online_capacity_induction=False,process_sta=False,full_goal_complete=False)
(S/'evidence.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))

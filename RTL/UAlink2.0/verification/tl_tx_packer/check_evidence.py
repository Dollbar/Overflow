"""Run: python3 [-O] verification/tl_tx_packer/check_evidence.py [--label peers].
Independently audits wire sequencing, exact source words, actual saved SRAM words,
source acknowledgements, stable stalls and actual-consumption credit publication.
Writes evidence.json; full protocol induction, UPLI splitting and process STA remain open.
"""
from pathlib import Path
from collections import deque
import argparse,hashlib,json,re,sys
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'model/tl'))
from credit_context import Context,decode_context
from receive_context import ReceiveContext
from credit_admission import requirements
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',default='peers');a=p.parse_args();S=R/'build/verification/tl_tx_packer';D=S/a.label
classes={'CONTROL':0,'DATA':1,'BYTE_ENABLE':2,'NOP':3,'MESSAGE':4,'POISON':5,'AUTH':6,'RESET':7}
def need(ok,msg):
    if not ok:raise ValueError(msg)
def pack(v,b):return sum(x<<(j*b) for j,x in enumerate(v))
def unpack(v,b):return [(v>>(j*b))&((1<<b)-1) for j in range(20)]
result=json.loads((D/'results.json').read_text());need(result['complete'] and len(result['results'])==16,'all 16 real configurations')
for name,digest in result['sources'].items():need(hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest,'actual compiled source changed '+name)
totals=dict(cycles=0,headers=0,data_halves=0,stored_words=0,fc=0,coalesced=0,fc_tail=0,tail_only=0,held_edges=0,cmd_returns=0,data_returns=0,nops=0)
for case in result['results']:
    b=D/f'w{case["width"]}_a{case["auth"]}_s{case["shared"]}_l{case["delay"]}';text=(b/'run.log').read_text();m=re.search(r'PASS actual packer .* cycles=(\d+) stored=(\d+) fc=(\d+) coalesced=(\d+) fc_tail=(\d+) tail_only=(\d+)',text);need(case['compile_exit']==case['run_exit']==0 and m,'actual terminal pass')
    headers=[[int(x,16) for x in (b/f'headers{e}.hex').read_text().splitlines()] for e in (0,1)];data=[[int(x,16) for x in (b/f'data{e}.hex').read_text().splitlines()] for e in (0,1)]
    txctx=[Context(auth=bool(case['auth'])) for _ in (0,1)];rxctx=[ReceiveContext(auth=bool(case['auth'])) for _ in (0,1)];queue=[deque(),deque()];seen=[[0,0],[0,0]];returned=[[0]*20 for _ in (0,1)];published=[[0]*20 for _ in (0,1)];caps=[2]*10+[4]*10;completion=[0,0];history=[];counts=dict(stored_words=0,fc=0,coalesced=0,fc_tail=0,tail_only=0)
    lines=(b/'trace.txt').read_text().splitlines();need(len(lines)%2==0,'complete endpoint pairs')
    for row,line in enumerate(lines):
        f=line.split();need(len(f)==23,'raw trace shape');v=[int(x) for x in f[:17]]+[int(x,16) for x in f[17:]]
        cycle,e,hi,di,pending,pv,taken,ht,dt,tt,ft,rxv,rxt,ret,count,tm,rm,tx,rx,word,av,cap,pub=v
        need(e==row%2 and [hi,di]==seen[e],'input index continuity');need(pending==len(txctx[e].pending),'actual transmit tenure equals independent context');need(count==len(queue[e]),'actual SRAM count equals expected stored words')
        need(not rxv or rxt,'no inflight rejection');need(not(ht or dt or tt or ft) or taken,'no input consumption without actual send')
        if row>=2:
            old=history[row-2]
            if old[5] and not old[6]:need(pv and tx==old[17] and tm==old[15],'candidate changed while stalled');totals['held_edges']+=1
        peer_row=row-2*case['delay']+(1 if e==0 else -1)
        expected=history[peer_row] if peer_row>=0 else None
        need(rxv==(expected[6] if expected else 0),'actual digital link valid delay')
        if rxv:need(rx==expected[17] and rm==expected[15],'actual digital link payload delay')
        if ret:
            need(queue[e] and word==queue[e].popleft(),'exact 600-bit stored word/owner retirement');release=unpack(word>>520,4);returned[e]=[x+y for x,y in zip(returned[e],release)];counts['stored_words']+=1
        if rxv:
            msg=tuple(((rx>>(256*j))&255) if rm&(1<<j) else None for j in (0,1));ob=rxctx[e].step(rx&((1<<256)-1),msg=msg)
            if ob['store']:queue[e].append((pack(ob['releases'],4)<<520)|(pack([classes[x] for x in ob['classes']],3)<<514)|(rm<<512)|rx)
        if taken:
            msg=tuple(((tx>>(256*j))&255) if tm&(1<<j) else None for j in (0,1));ob=txctx[e].step(tx&((1<<256)-1),msg=msg);nh=0;nd=0;nt=0
            if ob['classes'][0]=='CONTROL':
                dec,_,_=decode_context(tx&((1<<256)-1))
                if dec['fields']:
                    need(hi<len(headers[e]) and tx&((1<<256)-1)==headers[e][hi],'actual header source order');nh=1
                    need(all(n<=x for n,x in zip(requirements(headers[e][hi],shared=bool(case['shared'])),unpack(av,case['width']+1))),'actual header lacks full-tenure funding')
            for j,k in enumerate(ob['classes']):
                half=(tx>>(j*256))&((1<<256)-1)
                if k in ('DATA','BYTE_ENABLE'):
                    need(di+nd<len(data[e]) and half==data[e][di+nd],'actual Data/BE source word order');nd+=1
                if k=='AUTH':need(half==0,'actual supplied AuthTags fixture');nt+=1
            need((ht,dt,tt)==(nh,nd,nt),'source acknowledgements disagree with actual half-Flit classes');seen[e]=[hi+nh,di+nd]
            if pending==1:counts['coalesced' if ht else 'fc_tail' if ft else 'tail_only']+=1
            if not ht and not dt and not ft and tm==0 and tx==0:totals['nops']+=1
        if ft:
            counts['fc']+=1
            if tm==2:
                need(tx==((1|(case['shared']<<8))<<256) and published[e]==caps,'initial credit release complete ordering');completion[e]+=1
            else:
                low=tx&((1<<256)-1);need(tm==0 and 0<low<(1<<28),'FC field encoding')
                for group,(pos,nbits) in enumerate(((22,3),(16,3),(8,5),(0,5))):
                    value=(low>>pos)&((1<<(nbits+3))-1);lane=1+((value>>nbits)&3) if value&(1<<(nbits+2)) else 0;slot=group*5+lane;published[e][slot]+=value&((1<<nbits)-1);need(published[e][slot]<=caps[slot]+returned[e][slot],'FC credit predates actual retirement')
        history.append(v)
    need(completion==[1,1],'both real initializations complete')
    for e in (0,1):
        need(seen[e]==[len(headers[e]),len(data[e])] and not queue[e] and not txctx[e].pending and not rxctx[e].pending,'all independent sources and actual queues drained')
        need(published[e]==[x+y for x,y in zip(caps,returned[e])],'exact terminal credit conservation')
        totals['headers']+=seen[e][0];totals['data_halves']+=seen[e][1];totals['cmd_returns']+=sum(returned[e][:10]);totals['data_returns']+=sum(returned[e][10:])
    need(list(counts.values())==[int(x) for x in m.groups()[1:]],'raw event totals match TB')
    for k,x in counts.items():totals[k]+=x
    totals['cycles']+=int(m[1]);need(not case['auth'] or counts['coalesced']==0,'Auth forbids header with tail')
need(all(totals[k]>0 for k in ('coalesced','fc_tail','tail_only','held_edges','nops')),'meaningful packing/stall/catch coverage')
checks=json.loads((S/'checks/results.json').read_text());need(checks['complete'],'external checks complete')
for name,digest in checks['sources'].items():need(hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest,'checked source identity')
for kind,count in (('lint',2),('synthesis',2),('unit_fault',8),('peer_fault',32)):
    need(sum(x['kind']==kind for x in checks['results'])==count,'check denominator '+kind)
for row in checks['results']:
    need(row['passed'],'failed check '+str(row))
    if row['kind']=='unit_fault':
        d=S/('fault_'+row['name']);r=json.loads((d/'results.json').read_text());need(len(r['results'])==2,'two-width actual negative')
        for name,digest in r['sources'].items():need(hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest,'mutated source identity')
        for x in r['results']:need(x['compile_exit']==0 and x['run_exit']==1 and 'FATAL:' in (d/f'w{x["width"]}'/'run.log').read_text(),'actual unit mutation failure')
    if row['kind']=='peer_fault':need('FATAL:' in (S/'checks'/(row['name']+'_'+row['config']+'.log')).read_text(),'real peer mutation failure')
unit=json.loads((S/'unit/results.json').read_text());need(len(unit['results'])==2 and all(x['passed'] and x['vectors']==1585 for x in unit['results']),'actual healthy unit vectors')
for name,digest in unit['sources'].items():need(hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest,'unit compiled source identity')
physical=[]
for w in (8,16):
    m=json.loads((S/'checks'/f'synth_{w}.json').read_text())['modules']['tl_tx_packer'];clk=m['ports']['i_clk']['bits'];ff=0
    for c in m['cells'].values():
        if 'DFF' in c['type'] or 'LATCH' in c['type']:
            need(c['type'].startswith('$_SDFF') and c['connections']['C']==clk,'input-clock synchronous reset only');ff+=len(c['connections']['Q'])
    need(ff==4,'actual arbiter/hold state count');physical.append(dict(width=w,cells=len(m['cells']),ff_bits=ff))
small=json.loads((S/'small_credit/results.json').read_text());need(not small['complete'] and small['results'][0]['compile_exit']==0 and small['results'][0]['run_exit']==1,'actual undersized capacity remains open')
for name,digest in small['sources'].items():need(hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest,'undersized actual RTL identity')
need('h=0/0 d=0/0 tenure=0/0 fifo=0/0 shortfall=1/1' in (S/'small_credit/w8_a0_s0_l1/run.log').read_text(),'explicit oversized diagnostics without input loss')
gate=json.loads((S/'skill_gate.json').read_text());need(gate['ok'] and gate['errors']==0,'authored RTL quality gate')
out=dict(unit_vectors=3170,unit_negative_runs=16,peer_negative_runs=32,synthesis=physical,skill_errors=0,skill_advisories=gate['warnings'],actual_dual_configs=16,**totals,full_protocol_induction=False,request_response_queue_arbitration=False,oversized_transaction_handling=False,process_sta=False,full_goal_complete=False)
(S/'evidence.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))

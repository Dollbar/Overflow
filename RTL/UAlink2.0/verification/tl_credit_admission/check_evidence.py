"""Run: python3 [-O] verification/tl_credit_admission/check_evidence.py.
Audit actual wire/SRAM/credit traces and compiled-source identity. Writes evidence.json.
Next: capacity-aware packing/UPLI behavior, complete joint induction and process STA.
"""
from pathlib import Path
import hashlib,json,re,sys
R=Path(__file__).resolve().parents[2];S=R/'build/verification/tl_credit_admission';D=R/'build/verification/tl_receive_credit';sys.path.insert(0,str(R/'model/tl'))
from credit_admission import requirements

def need(ok,msg):
    if not ok:raise ValueError(msg)
def read(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def identity(result):
    for name,digest in result['sources'].items():need(sha(Path(name))==digest,'compiled source changed: '+name)
def unpack(word,b):return [(word>>(b*j))&((1<<b)-1) for j in range(20)]

def audit(label,cmdcredits):
    result=read(D/label/'results.json');identity(result);need(result['complete'] and len(result['results'])==16,'complete matrix '+label)
    totals=dict(cycles=0,stored=0,fc=0,cmd_returns=0,data_returns=0,wait_cycles=0,continuation_transfers=0)
    for case in result['results']:
        d=D/label/f'w{case["width"]}_a{case["auth"]}_s{case["shared"]}_l{case["latency"]}'
        m=re.search(r'PASS actual dual SRAM FC .* cycles=(\d+) stored=(\d+) fc=(\d+)',(d/'run.log').read_text());need(case['compile_exit']==case['run_exit']==0 and m is not None,'actual pass')
        app=[[int(x,16) for x in (d/f'app{e}.hex').read_text().splitlines()] for e in (0,1)]
        saved=[[int(x,16) for x in (d/f'expected{e}.hex').read_text().splitlines()] for e in (0,1)]
        idx=[[0,0],[0,0]];returns=[[0]*20 for _ in range(2)];published=[[0]*20 for _ in range(2)];complete=[0,0];fc=0;caps=[cmdcredits]*10+[4]*10
        trace=(d/'healthy_trace.txt').read_text().splitlines();guard=(d/'admission_trace.txt').read_text().splitlines();need(len(trace)==len(guard),'guard observations every actual edge')
        for number,(line,gline) in enumerate(zip(trace,guard)):
            f=line.split();v=[int(x) for x in f[:12]]+[int(x,16) for x in f[12:]]
            cycle,e,txi,rxi,rxv,rxt,taken,sel,ft,ret,release,count,rel,pending,av,tx=v
            need(e==number%2 and [txi,rxi]==idx[e],'actual index order');need(ret==release and (not rxv or rxt),'atomic receive/retirement');need(count<=case['depth'],'actual FIFO bound')
            if ret:
                need(rxi<len(saved[1-e]) and rel==saved[1-e][rxi]>>520,'saved owner release');idx[e][1]+=1
                returns[e]=[a+b for a,b in zip(returns[e],unpack(rel,4))]
            if taken and not sel:
                need(txi<len(app[e]) and tx==app[e][txi],'exact actual application transmit');idx[e][0]+=1
            need(ft==int(bool(taken and sel)),'FC commit equals wire transfer')
            if ft:
                if tx>>256:
                    need(tx==((1|(case['shared']<<8))<<256) and published[e]==caps,'complete only after initial credits');complete[e]+=1
                else:
                    need(0<tx<(1<<28),'actual FC format');fc+=1
                    for group,(pos,b) in enumerate(((22,3),(16,3),(8,5),(0,5))):
                        field=(tx>>pos)&((1<<(b+3))-1);lane=1+((field>>b)&3) if field&(1<<(b+2)) else 0;slot=group*5+lane;published[e][slot]+=field&((1<<b)-1)
                        need(published[e][slot]<=caps[slot]+returns[e][slot],'FC credit returned before real retirement')
            g=gline.split();c,side,send,gtaken,tenure,waiting,short,gsel=map(int,g[:8]);req,gav,cap=[int(x,16) for x in g[8:]]
            need((c,side,gtaken,gsel,gav)==(cycle,e,taken,sel,av),'actual guard observation matches port')
            actual_shared=bool(case['shared'] and unpack(cap,case['width']+1)[10]==8)
            want=requirements(tx&((1<<256)-1),shared=actual_shared) if tenure<=1 else (0,)*20
            need(tuple(unpack(req,6))==want,f'actual decoded whole-tenure requirements {d.name} cycle={cycle} side={e}')
            if taken and tenure<=1:need(all(n<=a for n,a in zip(want,unpack(av,case['width']+1))),'whole tenure backed by actual available credit')
            need(not short,'fitting pressure/mixed workload must not exceed capacity');need(not waiting or not taken,'waiting cannot change actual Tx state')
            if waiting:totals['wait_cycles']+=1
            if send and tenure>1:need(taken,'funded continuation stalled');totals['continuation_transfers']+=1
        need(complete==[1,1] and fc==int(m[3]),'actual complete/FC totals')
        for e in (0,1):
            need(idx[e]==[len(app[e]),len(saved[1-e])],'full application drain');need(published[e]==[a+b for a,b in zip(caps,returns[e])],'terminal exact logical credit conservation')
        totals['cycles']+=int(m[1]);totals['stored']+=int(m[2]);totals['fc']+=fc;totals['cmd_returns']+=sum(sum(x[:10]) for x in returns);totals['data_returns']+=sum(sum(x[10:]) for x in returns)
    return totals

pressure=audit('pressure_verified',2);mixed=audit('mixed_verified',1);need(pressure['wait_cycles']>0,'actual funding waits exercised')
guard=read(S/'guard_verified/results.json');identity(guard);need(len(guard['results'])==2 and all(x['passed'] and x['vectors']==8371 for x in guard['results']),'hand-derived RTL vectors')
checks=read(S/'checks_verified/results.json');identity(checks);need(checks['complete'],'actual structural/fault checks')
for kind,count in (('lint',2),('synth',2),('invalid_parameter',2),('guard_fault',6),('wrapper_fault',16)):
    need(sum(r['kind']==kind for r in checks['results'])==count,'complete check denominator '+kind)
for row in checks['results']:need(row['passed'],'failed external check')
for row in checks['results']:
    if row['kind']=='guard_fault':
        d=S/('checks_verified_fault_'+row['name']);r=read(d/'results.json');identity(r)
        for x in r['results']:need(x['compile_exit']==0 and x['run_exit']==1 and 'FATAL:' in (d/f'w{x["width"]}'/'run.log').read_text(),'real guard negative')
    if row['kind']=='wrapper_fault':need('unfunded header sent' in (S/'checks_verified'/('bypass_'+row['config']+'.log')).read_text(),'real wrapper gate negative')
physical=[]
for w in (8,16):
    m=read(S/'checks_verified'/f'synth_{w}.json')['modules']['tl_credit_admitted_port'];clk=m['ports']['i_clk']['bits'];ff=0
    for c in m['cells'].values():
        if 'DFF' in c['type'] or 'LATCH' in c['type']:
            need(c['type'].startswith('$_SDFF') and c['connections']['C']==clk,'all state synchronous reset on input clock');ff+=len(c['connections']['Q'])
    need(ff>1000,'actual stateful port synthesized');physical.append(dict(width=w,cells=len(m['cells']),ff_bits=ff))
small=read(D/'small_verified/results.json');identity(small);need(not small['complete'] and small['results'][0]['run_exit']==1,'oversized case still open')
need('pending=0/0 FIFO=0/0' in (D/'small_verified/w8_a0_s0_l1/run.log').read_text(),'oversized candidate held before tenure')
for line in (D/'small_verified/w8_a0_s0_l1/admission_trace.txt').read_text().splitlines()[-200:]:
    g=line.split();need(g[3]=='0' and g[4]=='0' and g[6]=='1','persistent explicit total capacity shortfall')
legacy=(D/'pressure_legacy/w8_a0_s0_l1/run.log').read_text();need('pending=5/5 FIFO=0/0' in legacy and 'liveness timeout' in legacy,'real pre-fix fitting-capacity deadlock')
gate=read(S/'skill_gate.json');need(gate['ok'] and gate['errors']==0,'authored artifact gate')
result=dict(whole_tenure_admission=True,pressure=pressure,mixed=mixed,dual_configs=32,guard_vectors=16742,guard_negative_runs=12,wrapper_negative_runs=16,synthesis=physical,skill_errors=0,skill_advisories=gate['warnings'],oversized_transaction_liveness=False,online_capacity_induction=False,full_protocol_induction=False,process_sta=False,full_goal_complete=False)
(S/'evidence.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))

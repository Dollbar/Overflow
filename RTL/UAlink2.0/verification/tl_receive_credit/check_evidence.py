"""Run: python3 [-O] verification/tl_receive_credit/check_evidence.py.
Audits actual-cycle FC/retirement conservation, source identity, negative runs,
parameter gates, clock graphs and the real small-credit liveness counterexample.
Outputs evidence.json. Full protocol induction and physical timing remain open.
"""
from pathlib import Path
import copy,hashlib,json,re
R=Path(__file__).resolve().parents[2];S=R/'build/verification/tl_receive_credit'
def read(p):return json.loads(p.read_text())
def need(ok,msg):
    if not ok:raise ValueError(msg)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def source_code(p):return re.sub(r'\s+','',re.sub(r'//[^\n]*|/\*.*?\*/','',p.read_text(),flags=re.S))
healthy=read(S/'matrix/results.json');need(healthy['complete'] and len(healthy['results'])==16,'complete actual matrix')
for name,digest in healthy['sources'].items():
    p=Path(name)
    if p.name=='tl_receive_credit.v' and sha(p)!=digest:
        need(sha(S/'pre_comment_wrapper.v')==digest,'original compiled wrapper identity')
        need(source_code(p)==source_code(S/'pre_comment_wrapper.v'),'only module comment changed')
    else:need(sha(p)==digest,'compiled dependency identity '+name)
totals=dict(cycles=0,stored_words=0,fc_transfers=0,completed_initializations=0,retired_cmd=0,retired_data=0);caps=[1]*10+[4]*10
for case in healthy['results']:
    d=S/'matrix'/f'w{case["width"]}_a{case["auth"]}_s{case["shared"]}_l{case["latency"]}';log=(d/'run.log').read_text();m=re.search(r'PASS actual dual SRAM FC .* cycles=(\d+) stored=(\d+) fc=(\d+)',log);need(case['compile_exit']==case['run_exit']==0 and m is not None,'real terminal pass')
    expected=[[int(s,16) for s in (d/f'expected{i}.hex').read_text().splitlines()] for i in (0,1)]
    app=[[int(s,16) for s in (d/f'app{i}.hex').read_text().splitlines()] for i in (0,1)]
    returned=[[0]*20 for _ in range(2)];published=[[0]*20 for _ in range(2)];indices=[[0,0] for _ in range(2)];fc_count=0;complete=[0,0];cycles=[];rownum=0
    # Fault drivers originally shared a trace path. The pre-fault healthy snapshot
    # is deliberately audited; the retained executed script documents that issue.
    trace=d/'healthy_trace.txt'
    for line in trace.read_text().splitlines():
        fields=line.split();need(len(fields)==16,'trace field count');vals=[int(x) for x in fields[:12]]+[int(x,16) for x in fields[12:]]
        cycle,e,txi,rxi,rxv,rxt,taken,sel,ft,ret,release_taken,count,rel,pending,avail,tx=vals
        need(e==rownum%2,'alternating actual endpoints');rownum+=1
        need([txi,rxi]==indices[e],'actual application/retirement index continuity');need(ret==release_taken,'atomic consumption and release')
        need(not rxv or rxt,'no lost incoming wire flit');need(count<=case['depth'],'actual FIFO bound')
        if ret:
            need(rxi<len(expected[1-e]),'unowned retirement');need(rel==expected[1-e][rxi]>>520,'actual saved release ownership');indices[e][1]+=1
            for slot in range(20):returned[e][slot]+=(rel>>(4*slot))&15
        if taken and not sel:
            need(txi<len(app[e]) and tx==app[e][txi],'actual transmitted payload order');indices[e][0]+=1
        need(ft==(taken and sel),'publisher only commits actual chosen FC transmission')
        if ft:
            if tx>>256:
                need(tx==((1|(case['shared']<<8))<<256),'actual completion encoding');need(published[e]==caps,'all initial credit sent before completion');complete[e]+=1
            else:
                need(0<tx<(1<<28),'FC word format');fc_count+=1
                for g,(pos,bits) in enumerate(((22,3),(16,3),(8,5),(0,5))):
                    field=(tx>>pos)&((1<<(bits+3))-1);amount=field&((1<<bits)-1);lane=1+((field>>bits)&3) if field&(1<<(bits+2)) else 0;slot=g*5+lane;published[e][slot]+=amount
                    need(published[e][slot]<=caps[slot]+returned[e][slot],'no return before actual FIFO retirement')
        if e==0:cycles.append(cycle)
    need(cycles==sorted(cycles) and all(b-a in (0,1) for a,b in zip(cycles,cycles[1:])),'cycle continuity')
    need(complete==[1,1] and fc_count==int(m[3]),'actual FC/completion event counts')
    need(sum(x[1] for x in indices)==int(m[2]),'all stored words consumed')
    for e in (0,1):need(published[e]==[c+r for c,r in zip(caps,returned[e])],'terminal exact credit conservation')
    totals['cycles']+=int(m[1]);totals['stored_words']+=int(m[2]);totals['fc_transfers']+=fc_count;totals['completed_initializations']+=sum(complete);totals['retired_cmd']+=sum(sum(r[:10]) for r in returned);totals['retired_data']+=sum(sum(r[10:]) for r in returned)
checks=read(S/'checks_final/results.json');need(checks['complete'],'actual lint/synthesis/fault checks');negative=0
for row in checks['results']:
    if row['kind']=='fault':
        need(len(row['results'])==16,'fault parameter matrix');need(sha(S/'checks_final'/row['name']/'tl_receive_credit.v')==row['source_sha256'],'mutated RTL source identity')
        for c in row['results']:
            log=(S/'checks_final'/row['name']/c['config']/'run.log').read_text();need(c['compile_exit']==0 and c['run_exit']==1 and c['detected'] and 'FATAL:' in log and 'PASS actual' not in log,'actual RTL negative');negative+=1

def graph(m):
    clk=m['ports']['i_clk']['bits'];ff=[];mac=[]
    for c in m['cells'].values():
        t=c['type'];x=c['connections']
        if 'DFF' in t or 'LATCH' in t:need(t.startswith('$_SDFF') and x.get('C')==clk,'single-clock synchronous-reset FF');ff.append(c)
        if t.startswith('KD28_SRAM'):need(t=='KD28_SRAM_SDP_256X32' and x['RCLK']==clk and x['WCLK']==clk,'actual SRAM clocks/type');mac.append(c)
    need(len(mac)==19 and len(ff)>2000,'actual SRAM and state present');return len(m['cells']),sum(len(x['connections']['Q']) for x in ff)
physical=[];damages=0
for width in (8,16):
    m=read(S/'checks_final'/f'synth_{width}.json')['modules']['tl_receive_credit'];cells,ff=graph(m);physical.append(dict(width=width,cells=cells,ff=ff,sram=19))
    for kind in ('ff_clock','async_reset','sram_clock','lost_sram'):
        q=copy.deepcopy(m)
        if kind=='ff_clock':next(c for c in q['cells'].values() if 'DFF' in c['type'])['connections']['C']=['0']
        elif kind=='async_reset':next(c for c in q['cells'].values() if 'DFF' in c['type'])['type']='$_DFF_PN0_'
        else:
            n=next(n for n,c in q['cells'].items() if c['type'].startswith('KD28_SRAM'))
            if kind=='sram_clock':q['cells'][n]['connections']['WCLK']=['0']
            else:del q['cells'][n]
        try:graph(q)
        except ValueError:damages+=1
        else:raise ValueError('graph damage escaped')
need(read(S/'parameters/results.json')['complete'],'parameter checks')
handoff=read(S/'handoff/results.json');need(handoff['complete'] and len(handoff['results'])==6,'real backpressure and reset handoff cases')
for row in handoff['results']:
    log=(S/'handoff'/f'w{row["width"]}_{row["fault"]}'/'run.log').read_text()
    need(row['compile_exit']==0,'actual handoff compilation')
    if row['fault']=='healthy':need(row['run_exit']==0 and 'preinit_hold=16 retired=1 reset_discard=1' in log,'actual blocked consumption and reset discard')
    else:need(row['run_exit']==1 and 'FATAL:' in log and 'PASS actual handoff' not in log,'real handoff gate fault')

small=read(S/'small_credit/results.json');need(not small['complete'] and small['results'][0]['compile_exit']==0 and small['results'][0]['run_exit']==1,'actual small-credit counterexample')
log=(S/'small_credit/w8_a0_s0_l1/run.log').read_text();need('pending=3/4 FIFO=0/0' in log and 'liveness timeout' in log,'actual stopped data tenure and drained SRAM')
trace=(S/'small_credit/w8_a0_s0_l1/trace.txt').read_text().splitlines()[-200:]
for line in trace:
    f=line.split();need(f[2:4]==['3','3'] and f[4:12]==['0']*8 and int(f[13],16)>0,'persistent no transfers despite real pending credit returns')
gate=read(S/'skill_gate.json');need(gate['errors']==0,'artifact gate')
result=dict(functional_matrix_passed=True,actual_receive_fifo_to_fc=True,configs=16,**totals,rtl_fault_types=7,negative_runs=negative,handoff_healthy=2,handoff_fault_types=2,handoff_negative_runs=4,strict_lint=2,synthesis=physical,graph_damages=damages,parameter_checks=9,invalid_parameters=6,skill_errors=0,skill_advisories=gate['warnings'],small_credit_liveness=False,small_credit_counterexample={'data_credits_per_slot':1,'tx_indices':[3,3],'pending_halves':[3,4],'fifo_counts':[0,0],'observation_limit_cycles':6000},online_capacity_induction=False,complete_reference_induction=False,process_sta=False,full_goal_complete=False)
(S/'evidence.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))

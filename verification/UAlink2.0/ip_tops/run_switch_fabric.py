#!/usr/bin/env python3
"""Production crossbar regression; all fault copies remain isolated.
Run: python3 verification/ip_tops/run_switch_fabric.py --label NEW [--faults] [--static]
Outputs: build/verification/ip_tops/switch_fabric/NEW with exact RTL/TB snapshots, vectors, logs and hashes.
Next: review and integrate the candidate into the production arbiter/top separately.
"""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import random
import re
import subprocess
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
HERE=Path(__file__).resolve().parent
SHELL_TB='''module tb;
reg rstn=0;wire ready,valid,implemented,error;wire [511:0] data;
switch_fabric dut(.i_clk(1'b0),.i_rstn(rstn),.i_enable(1'b1),.i_valid(1'b1),.i_data(512'h123),.i_meta(128'd0),.o_ready(ready),.o_valid(valid),.o_data(data),.o_meta(),.o_implemented(implemented),.o_error(error));
initial begin #1;rstn=1;#1;if(!implemented||!ready||!valid||data!==512'h123)$fatal(1,"FABRIC_UNIMPLEMENTED");$finish;end
endmodule
'''

def expected(p,w,rstn,valid,data,last,route,select,ready):
    if not rstn:return 0,0,0,0,0
    edges={(e,s) for e in range(p) for s in range(p) if select>>(e*p+s)&1}
    bad_rows={e for e in range(p) if sum(a==e for a,b in edges)>1}
    bad_sources={s for s in range(p) if sum(b==s for a,b in edges)>1}
    accepted={(e,s) for e,s in edges if e not in bad_rows and s not in bad_sources and route>>(s*p+e)&1}
    er=sum(((ready>>e)&1)<<s for e,s in accepted)
    ev=sum(((valid>>s)&1)<<e for e,s in accepted)
    ed=sum(((data>>(s*w))&((1<<w)-1))<<(e*w) for e,s in accepted)
    el=sum(((last>>s)&1)<<e for e,s in accepted)
    return er,ev,ed,el,int(bool(bad_rows or bad_sources))

def vectors(path,p,w):
    rng=random.Random(3107+p*101+w);count=0;groups={}
    with path.open('w') as f:
        def emit(group,rstn,valid,data,last,route,select,ready,want=None):
            nonlocal count
            inputs=(rstn,valid,data,last,route,select,ready)
            outputs=expected(p,w,*inputs) if want is None else want
            f.write(' '.join(format(x,'x') for x in inputs+outputs)+'\n');count+=1;groups[group]=groups.get(group,0)+1
        allp=(1<<p)-1;allmatrix=(1<<(p*p))-1;data=rng.getrandbits(p*w)
        emit('literal_reset',0,allp,(1<<(p*w))-1,allp,allmatrix,allmatrix,allp,(0,0,0,0,0))
        emit('literal_none',1,allp,data,allp,allmatrix,0,allp,(0,0,0,0,0))
        # Hand-calculated P3 mapping: e0<-s2, e1<-s0, e2<-s1. One source has a bubble.
        if p==3 and w==7:emit('literal_asymmetric',1,5,(0x56<<14)|(0x34<<7)|0x12,3,0x62,0x8c,5,(6,3,(0x34<<14)|(0x12<<7)|0x56,6,0))
        for s in range(p):
            for e in range(p):
                route=1<<(s*p+e);select=1<<(e*p+s)
                emit('reset_selected_pair',0,allp,(1<<(p*w))-1,allp,route,select,allp,(0,0,0,0,0))
                for v,l,r in itertools.product((0,1),repeat=3):
                    word=rng.getrandbits(p*w)|(1<<(s*w))
                    emit('pair_handshake',1,v<<s,word,l<<s,route,select,r<<e)
                    emit('route_mismatch',1,v<<s,word,l<<s,0,select,r<<e)
                for bit in range(w):
                    emit('every_data_bit',1,1<<s,1<<(s*w+bit),1<<s,route,select,1<<e)
        if p<=4:
            for permutation in itertools.permutations(range(p)):
                select=sum(1<<(e*p+s) for e,s in enumerate(permutation));route=sum(1<<(s*p+e) for e,s in enumerate(permutation))
                for valid in range(1<<p):
                    for ready in range(1<<p):emit('parallel_permutations',1,valid,rng.getrandbits(p*w),valid^allp,route,select,ready)
        if p<=3:
            routes=(0,allmatrix,sum(1<<(s*p+s) for s in range(p)))
            for select in range(1<<(p*p)):
                for route in routes:
                    emit('all_select_patterns',1,allp,rng.getrandbits(p*w),allp,route,select,allp)
                    emit('conflicts_during_bubbles',1,0,rng.getrandbits(p*w),allp,route,select,allp)
        for _ in range(500):emit('random_graph',rng.randrange(2),rng.getrandbits(p),rng.getrandbits(p*w),rng.getrandbits(p),rng.getrandbits(p*p),rng.getrandbits(p*p),rng.getrandbits(p))
        if p>=3:
            select=(1<<0)|(1<<1)|(1<<(2*p+2));route=(1<<0)|(1<<p)|(1<<(2*p+2))
            emit('unrelated_path_survives',1,allp,data,allp,route,select,allp)
            select=(1<<0)|(1<<p)|(1<<(2*p+2));emit('duplicate_source',1,allp,data,allp,route,select,allp)
    return dict(checks=count,groups=groups)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--label',required=True);parser.add_argument('--shell-red',action='store_true');parser.add_argument('--faults',action='store_true');parser.add_argument('--static',action='store_true');a=parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',a.label):parser.error('fresh safe label required')
    stage=ROOT/'build/verification/ip_tops/switch_fabric'/a.label;stage.mkdir(parents=True,exist_ok=False)
    source=ROOT/'rtl/switch/switch_fabric.v'
    blob=source.read_bytes();tb=SHELL_TB.encode() if a.shell_red else (HERE/'switch_fabric_tb.sv').read_bytes()
    (stage/'source.v').write_bytes(blob);(stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    cases=[(1,512,None)] if a.shell_red else [(1,1,None),(1,7,None),(1,544,None),(2,1,None),(2,32,None),(2,544,None),(3,7,None),(3,544,None),(4,1,None),(4,32,None),(4,544,None),(5,13,None),(8,65,None)]
    if a.faults:cases +=[(3,7,f) for f in ('data_valid_gate','route_transpose','data_bit','conflict','ready','reset')]
    result=dict(source_sha256=hashlib.sha256(blob).hexdigest(),source=str(source.relative_to(ROOT)),shell_red=a.shell_red,cases=[],passed=True)
    for p,w,fault in cases:
        name=f'p{p}_w{w}'+('_'+fault if fault else '');folder=stage/name;folder.mkdir();rtl=blob
        if fault:
            before,after={
                'data_valid_gate':('= i_data[source*DATA_WIDTH +: DATA_WIDTH];',"= i_valid[source]?i_data[source*DATA_WIDTH +: DATA_WIDTH]:{DATA_WIDTH{1'b0}};"),
                'route_transpose':('i_route_match[source*PORTS+egress]','i_route_match[egress*PORTS+source]'),
                'data_bit':('= i_data[source*DATA_WIDTH +: DATA_WIDTH];',"= i_data[source*DATA_WIDTH +: DATA_WIDTH] ^ ({{(DATA_WIDTH-1){1'b0}},1'b1} << (DATA_WIDTH-1));"),
                'conflict':('!row_conflict[egress] && !column_conflict[source]',"1'b1"),
                'ready':('= i_ready[egress];','= i_ready[source];'),
                'reset':('if (i_rstn) begin',"if (1'b1) begin"),
            }[fault]
            text=rtl.decode()
            if text.count(before)!=1:raise ValueError('fault anchor absent/ambiguous '+fault)
            rtl=text.replace(before,after).encode()
        (folder/'switch_fabric.v').write_bytes(rtl);(folder/'tb.sv').write_bytes(tb)
        case=dict(name=name,ports=p,width=w,fault=fault)
        if not a.shell_red:case['coverage']=vectors(folder/'vectors.txt',p,w)
        for phase,cmd in [('compile',['iverilog','-g2012','-s','tb',*([] if a.shell_red else [f'-Ptb.PORTS={p}',f'-Ptb.DATA_WIDTH={w}']),'-o','sim.vvp','switch_fabric.v','tb.sv']),('run',['vvp','sim.vvp'])]:
            with (folder/(phase+'.log')).open('w') as log:
                try:code=subprocess.run(cmd,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=45).returncode
                except subprocess.TimeoutExpired:code=124
            case[phase]=dict(command=cmd,exit=code)
            if phase=='compile' and code:break
        log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
        case['passed']=case['compile']['exit']==0 and case.get('run',{}).get('exit')==(1 if fault else 0) and ('FABRIC_MISMATCH' if fault else 'FABRIC_PASS') in log
        case['artifacts_sha256']={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in folder.iterdir() if f.is_file()}
        result['cases'].append(case);result['passed'] &=case['passed'];print(name,case['passed'],flush=True)
    if a.static and not a.shell_red:
        result['static']=[]
        for p,w in ((1,1),(3,7),(4,544),(8,65)):
            folder=stage/f'static_p{p}_w{w}';folder.mkdir();(folder/'switch_fabric.v').write_bytes(blob)
            script=f'read_verilog switch_fabric.v\nhierarchy -check -top switch_fabric -chparam PORTS {p} -chparam DATA_WIDTH {w}\nproc\nopt\nmemory_map\nopt\ncheck -assert\nstat\n';(folder/'check.ys').write_text(script)
            for tool,cmd in [('g2001',['iverilog','-g2001','-s','switch_fabric',f'-Pswitch_fabric.PORTS={p}',f'-Pswitch_fabric.DATA_WIDTH={w}','-o','compile.vvp','switch_fabric.v']),('lint',['verilator','--lint-only','-Wall','--top-module','switch_fabric',f'-GPORTS={p}',f'-GDATA_WIDTH={w}','switch_fabric.v']),('yosys',['yosys','-Q','-T','-s','check.ys'])]:
                with (folder/(tool+'.log')).open('w') as log:
                    try:code=subprocess.run(cmd,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=45).returncode
                    except subprocess.TimeoutExpired:code=124
                result['static'].append(dict(ports=p,width=w,tool=tool,command=cmd,exit=code));result['passed'] &=code==0
    result['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
    (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

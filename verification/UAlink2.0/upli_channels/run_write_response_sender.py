#!/usr/bin/env python3
"""Run: python3 verification/upli_channels/run_write_response_sender.py --label NEW.
Outputs fresh build/verification/upli_channels/write_response_sender/NEW source snapshots,
independent vectors, logs and hashes. --rtl selects a candidate; normal dependencies are
production bank/Write leaf/parity. Next connect actual responses to station TX.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
from write_response_sender_reference import generate

ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
HERE=Path(__file__).resolve().parent


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--label',required=True)
    p.add_argument('--ports',type=int,choices=(1,2,4),default=4)
    p.add_argument('--width',type=int,choices=range(3,17),default=4)
    p.add_argument('--init-cycles',type=int,choices=range(2,16),default=2)
    p.add_argument('--rtl',type=Path,default=ROOT/'rtl/upli/upli_write_response_sender.v')
    p.add_argument('--fault',choices=('debit','phase','high_tag'))
    a=p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
    stage=ROOT/'build/verification/upli_channels/write_response_sender'/a.label
    stage.mkdir(parents=True,exist_ok=False)
    report={'label':a.label,'sources':{},'commands':{},'ports':a.ports,'width':a.width,'init_cycles':a.init_cycles}
    source_dir=stage/'source';source_dir.mkdir()
    sources=[a.rtl.resolve()]+[ROOT/f'rtl/upli/{name}.v' for name in ('upli_credit_bank','upli_write_response_channel','upli_parity')]
    compiled=[]
    for src in sources+[HERE/'write_response_sender_tb.sv',HERE/'write_response_sender_reference.py',Path(__file__)]:
        if not src.exists():
            report.setdefault('missing_sources',[]).append(str(src));continue
        blob=src.read_bytes();target=source_dir/src.name;target.write_bytes(blob)
        report['sources'][str(src)]=hashlib.sha256(blob).hexdigest()
        if src in sources:compiled.append(target)
    if a.fault:
        target=source_dir/'upli_write_response_sender.v';code=target.read_text()
        old,new={
            'debit':('.i_send_valid(o_valid)',".i_send_valid(1'b0)"),
            'phase':('else if (reg_phase_known) reg_phase <= next_phase;','else if (reg_phase_known && o_valid) reg_phase <= next_phase;'),
            'high_tag':('.i_tag(i_candidate_payload[34:24])',".i_tag({1'b0,i_candidate_payload[33:24]})")}[a.fault]
        if code.count(old)!=1:raise ValueError('real source mutation anchor must match once')
        target.write_text(code.replace(old,new));report['fault']=a.fault
    capacities=[]
    for port in range(a.ports):capacities.extend([0 if port==0 else 2,1,3,(1<<(min(a.width,5)-1))+1,min((1<<a.width)-1,19)])
    capacity_bits=a.ports*5*a.width
    encoded=sum(cap<<(index*a.width) for index,cap in enumerate(capacities))
    report['reference']=generate(stage/'vectors.txt',a.ports,a.width,a.init_cycles,capacities)
    def run(name,cmd):
        cmd=[str(c) for c in cmd];start=time.monotonic()
        with (stage/(name+'.log')).open('w') as log:
            try:rc=subprocess.run(cmd,cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=60).returncode
            except subprocess.TimeoutExpired:rc=124
        report['commands'][name]={'command':cmd,'returncode':rc,'seconds':round(time.monotonic()-start,3)}
        return rc
    overrides=[f'-Pwrite_response_sender_tb.PORTS={a.ports}',f'-Pwrite_response_sender_tb.WIDTH={a.width}',f'-Pwrite_response_sender_tb.INIT_CYCLES={a.init_cycles}',f"-Pwrite_response_sender_tb.CAPACITIES={capacity_bits}'h{encoded:x}"]
    rc=run('compile',['iverilog','-g2012','-s','write_response_sender_tb',*overrides,'-o','simulation.vvp',source_dir/'write_response_sender_tb.sv',*compiled])
    if rc==0:run('simulate',['vvp','simulation.vvp','+VECTORS=vectors.txt',f'+ROWS={report["reference"]["rows"]}'])
    if rc==0 and not a.fault:
        params=[f'-Pupli_write_response_sender.C_NUM_PORTS={a.ports}',f'-Pupli_write_response_sender.C_CREDIT_WIDTH={a.width}',f'-Pupli_write_response_sender.C_INIT_CYCLES={a.init_cycles}',f"-Pupli_write_response_sender.C_CAPACITIES={capacity_bits}'h{encoded:x}"]
        run('g2001',['iverilog','-g2001','-s','upli_write_response_sender',*params,'-o','elab.vvp',*compiled])
        params=[f'-GC_NUM_PORTS={a.ports}',f'-GC_CREDIT_WIDTH={a.width}',f'-GC_INIT_CYCLES={a.init_cycles}',f"-GC_CAPACITIES={capacity_bits}'h{encoded:x}"]
        run('lint',['verilator','--lint-only','--language','1364-2001','-Wall','--top-module','upli_write_response_sender',*params,*compiled])
        script='read_verilog '+' '.join(json.dumps(str(f)) for f in compiled)+f'; chparam -set C_NUM_PORTS {a.ports} -set C_CREDIT_WIDTH {a.width} -set C_INIT_CYCLES {a.init_cycles} -set C_CAPACITIES {capacity_bits}\\\'h{encoded:x} upli_write_response_sender; hierarchy -check -top upli_write_response_sender; proc; opt; memory_map; opt; check -assert; stat; write_json netlist.json'
        script=script.replace("\\'", "'")
        run('yosys',['yosys','-Q','-T','-p',script])
    log=(stage/'simulate.log').read_text() if (stage/'simulate.log').exists() else ''
    report['passed']=all(c['returncode']==0 for c in report['commands'].values()) and 'WR_SENDER_PASS' in log
    report['actual_counts']={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',log)}
    if a.fault:report['passed']=rc==0 and report['commands'].get('simulate',{}).get('returncode')==1 and any(word in log for word in ('WR_SENDER_PRE','WR_SENDER_POST','WR_SENDER_JOURNAL','WR_SENDER_CREDIT_UNDERFLOW'))
    else:
        report['passed']=report['passed'] and report['actual_counts'].get('sends')==report['reference']['coverage']['accepted'] and report['actual_counts'].get('rows')==report['reference']['rows']
    if (stage/'netlist.json').exists():
        net=json.loads((stage/'netlist.json').read_text())['modules'];counts={}
        def visit(name):
            module=net[name];kind=module.get('attributes',{}).get('hdlname',name).split()[0].lstrip('\\');counts[kind]=counts.get(kind,0)+1
            for cell in module['cells'].values():
                if cell['type'] in net:visit(cell['type'])
        visit('upli_write_response_sender');report['hierarchy_counts']=counts
        report['latches']=sum('latch' in c['type'].lower() for m in net.values() for c in m['cells'].values())
        report['passed']=report['passed'] and counts.get('upli_credit_bank')==1 and counts.get('upli_write_response_channel')==1 and counts.get('upli_parity')==1 and report['latches']==0
    report['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
    (stage/'result.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS' if report['passed'] else 'FAIL',stage/'result.json')
    return 0 if report['passed'] else 1

if __name__=='__main__':raise SystemExit(main())

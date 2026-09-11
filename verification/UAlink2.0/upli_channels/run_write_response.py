#!/usr/bin/env python3
"""Run: python3 verification/upli_channels/run_write_response.py --label NEW [--fault FAULT].
Outputs fresh ROOT/build/verification/upli_channels/write_response/NEW vectors, logs and hashes.
Default RTL/parity come directly from ROOT/rtl/upli; explicit --rtl/--parity select candidates.
Next connect actual credit-qualified Write Response events; this unit is TX fields/parity only.
"""
import argparse
import hashlib
import json
import random
import re
import subprocess
import time
from pathlib import Path

ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
HERE=Path(__file__).resolve().parent
FIELDS=(('type_info',2),('tag',11),('status',4),('src',10),('dst',10),('port',2),('vc',2),('pool',1),('auth_tag',64))


def packed(fields):
    value=0
    for word,width in fields:
        if not 0<=word<(1<<width):raise ValueError('vector width')
        value=(value<<width)|word
    return value


def write_vectors(path):
    cases=[]
    # Two literal diagnostic patterns include all high ID/Tag/Auth bits.
    literal=[3,0x5a5,8,0x201,0x3a5,3,2,1,0x800000000000005a]
    for rstn in (0,1):
        for valid in (0,1):
            cases.append((rstn,valid,literal.copy()))
            cases.append((rstn,valid,[0]*len(FIELDS)))
            cases.append((rstn,valid,[(1<<w)-1 for _,w in FIELDS]))
    # Walking one and walking zero independently cover each of all 106 native field bits.
    for index,(_,width) in enumerate(FIELDS):
        for bit in range(width):
            for high in (False,True):
                values=[((1<<w)-1 if high else 0) for _,w in FIELDS]
                values[index]^=1<<bit
                for rstn,valid in ((1,1),(1,0),(0,1),(0,0)):cases.append((rstn,valid,values.copy()))
    # Field preservation for all encoded types/statuses/ports/VC/pool; these are not
    # assertions that every combination is a legal command or an enabled port.
    for typ in range(4):
        for status in range(16):
            for port in range(4):
                for vc in range(4):
                    for pool in (0,1):
                        values=literal.copy();values[0]=typ;values[2]=status;values[5:8]=[port,vc,pool]
                        cases.append((1,1,values))
    rng=random.Random(0x5752525350)
    for _ in range(600):cases.append((rng.randrange(2),rng.randrange(2),[rng.getrandbits(w) for _,w in FIELDS]))
    with path.open('w') as out:
        for rstn,valid,fields in cases:
            active=rstn & valid
            output=fields if active else [0]*len(FIELDS)
            # Population counts over explicit fields, independent of RTL packing/helper.
            control=sum(word.bit_count() for word in output[:8])%2
            auth=output[8].bit_count()%2
            inp=packed([(rstn,1),(valid,1)]+[(v,w) for v,(_,w) in zip(fields,FIELDS)])
            expected=packed([(active,1)]+[(v,w) for v,(_,w) in zip(output,FIELDS)]+[(active,1),(auth,1),(control,1)])
            out.write(f'{inp:x} {expected:x}\n')
    return len(cases)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label',required=True)
    parser.add_argument('--rtl',type=Path,default=ROOT/'rtl/upli/upli_write_response_channel.v')
    parser.add_argument('--parity',type=Path,default=ROOT/'rtl/upli/upli_parity.v')
    parser.add_argument('--fault',choices=('tag_msb','auth_drop','pool_parity','valid_reset','status'))
    args=parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',args.label):parser.error('safe fresh label required')
    stage=ROOT/'build/verification/upli_channels/write_response'/args.label
    stage.mkdir(parents=True,exist_ok=False)
    rtl=args.rtl.resolve();parity=args.parity.resolve();tb=HERE/'write_response_tb.sv'
    sources={p.resolve():p.read_bytes() for p in (rtl,parity,tb,Path(__file__))}
    report={'label':args.label,'sources':{str(p):hashlib.sha256(b).hexdigest() for p,b in sources.items()},'commands':{},'field_bits':106}
    tested=rtl
    if args.fault:
        before,after={
            'tag_msb':('assign o_tag = i_tag & {11{o_valid}};',"assign o_tag = {1'b0,i_tag[9:0]} & {11{o_valid}};"),
            'auth_drop':('assign o_auth_tag = i_auth_tag & {64{o_valid}};',"assign o_auth_tag = 64'd0;"),
            'pool_parity':('o_port,o_vc,o_pool}',"o_port,o_vc,1'b0}"),
            'valid_reset':('assign o_valid = i_rstn && i_valid;','assign o_valid = i_valid;'),
            'status':('assign o_status = i_status & {4{o_valid}};',"assign o_status = (i_status ^ 4'b1000) & {4{o_valid}};")}[args.fault]
        code=sources[rtl].decode()
        if code.count(before)!=1:raise ValueError('actual fault anchor must match exactly once')
        tested=stage/'upli_write_response_channel.v';tested.write_text(code.replace(before,after))
        report['fault']={'kind':args.fault,'mutant_sha256':hashlib.sha256(tested.read_bytes()).hexdigest()}
    report['rows']=write_vectors(stage/'vectors.txt')
    def run(name,cmd):
        command=[str(x) for x in cmd];start=time.monotonic()
        with (stage/(name+'.log')).open('w') as out:
            try:rc=subprocess.run(command,cwd=stage,stdout=out,stderr=subprocess.STDOUT,timeout=60).returncode
            except subprocess.TimeoutExpired:rc=124
        report['commands'][name]={'command':command,'returncode':rc,'seconds':round(time.monotonic()-start,3)}
        return rc
    compile_rc=run('compile',['iverilog','-g2012','-s','write_response_tb','-o','simulation.vvp',tb,tested,parity])
    if compile_rc==0:run('simulate',['vvp','simulation.vvp','+VECTORS=vectors.txt',f'+ROWS={report["rows"]}'])
    if compile_rc==0 and not args.fault:
        run('g2001',['iverilog','-g2001','-s','upli_write_response_channel','-o','elaborated.vvp',tested,parity])
        run('lint',['verilator','--lint-only','--language','1364-2001','-Wall','--top-module','upli_write_response_channel',tested,parity])
        script='read_verilog '+json.dumps(str(tested))+' '+json.dumps(str(parity))+'; hierarchy -check -top upli_write_response_channel; proc; opt; memory_map; opt; check -assert; stat; write_json netlist.json'
        run('yosys',['yosys','-Q','-T','-p',script])
    log=(stage/'simulate.log').read_text() if (stage/'simulate.log').exists() else ''
    report['passed']=all(c['returncode']==0 for c in report['commands'].values()) and f'WRITE_RESPONSE_PASS rows={report["rows"]}' in log
    if args.fault:report['passed']=compile_rc==0 and report['commands'].get('simulate',{}).get('returncode')==1 and 'WRITE_RESPONSE_COMPARE' in log
    if (stage/'netlist.json').exists():
        modules=json.loads((stage/'netlist.json').read_text())['modules']
        top=modules['upli_write_response_channel'];instances=[c for c in top['cells'].values() if c['type'] in modules]
        report['parity_instances']=len(instances)
        report['latches']=sum('latch' in c['type'].lower() for m in modules.values() for c in m['cells'].values())
        report['passed']=report['passed'] and len(instances)==1 and report['latches']==0
    report['changed_sources']=[str(p) for p,b in sources.items() if not p.exists() or p.read_bytes()!=b]
    report['passed']=report['passed'] and not report['changed_sources']
    report['artifacts_sha256']={str(p.relative_to(stage)):hashlib.sha256(p.read_bytes()).hexdigest() for p in stage.rglob('*') if p.is_file()}
    (stage/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS' if report['passed'] else 'FAIL',stage/'result.json')
    return 0 if report['passed'] else 1

if __name__=='__main__':raise SystemExit(main())

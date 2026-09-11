#!/usr/bin/env python3
"""Run: python3 verification/upli_channels/run_orig_data.py --label NEW --integration.
Output: build/verification/upli_channels/orig_data/NEW vectors, logs and source hashes.
Native RTL is compiled directly from ROOT/rtl; --rtl explicitly overrides the OrigData leaf.
Next integrate the typed Request and OrigData outputs of one shared sender.
"""
import argparse
import hashlib
import json
import random
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
HERE=Path(__file__).resolve().parent

def packed(fields):
    result=0
    for value,width in fields: result=(result<<width)|value
    return result

def vectors(path):
    rng=random.Random(0xDA7A512)
    rows=[]
    # Check each physical data lane with all BE masked and unmasked, both valid states.
    for bit in range(512):
        for valid in (0,1):
            for be in (0,(1<<64)-1):rows.append([valid,bit%4,1<<bit,be,bit%4,bit%2,(bit//2)%2,(bit//4)%4,bit%2])
    for bit in range(64):
        for valid in (0,1):rows.append([valid,3,(1<<512)-1,1<<bit,3,1,1,3,1])
    # All nine native controls independently exercised; poison remains a field.
    for controls in range(512):
        rows.append([1,(controls>>4)&3,0,0,(controls>>2)&3,controls&1,(controls>>1)&1,(controls>>6)&3,(controls>>8)&1])
    widths=(1,2,512,64,2,1,1,2,1)
    for _ in range(1000):rows.append([rng.getrandbits(w) for w in widths])
    with path.open('w') as f:
        for row in rows:
            v,p,d,be,off,last,err,vc,pool=row
            # Integer population count is independent of RTL reduction XOR.
            dp=sum((((d>>(64*i))&((1<<64)-1)).bit_count()%2)<<i for i in range(8))
            fp=(p.bit_count()+off.bit_count()+last+err+vc.bit_count()+pool)%2
            inp=packed(zip(row,widths))
            out=packed(list(zip(row,widths))+[(v,1),(dp,8),(be.bit_count()%2,1),(fp,1)])
            f.write(f'{inp:x} {out:x}\n')
    return len(rows)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label',required=True)
    parser.add_argument('--rtl',type=Path,default=ROOT/'rtl/upli/upli_orig_data_channel.v')
    parser.add_argument('--fault',choices=('data_msb','masked_parity','poison'))
    parser.add_argument('--integration',action='store_true')
    args=parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',args.label):parser.error('safe fresh label required')
    if args.fault and args.integration:parser.error('run each isolated fault separately from healthy integration')
    stage=ROOT/'build/verification/upli_channels/orig_data'/args.label
    stage.mkdir(parents=True,exist_ok=False)
    report=dict(label=args.label,sources={},commands={},source_mode='direct read-only source; only faults create an isolated mutant')
    tracked={}
    def track(path):
        path=path.resolve()
        blob=path.read_bytes()
        tracked[path]=hashlib.sha256(blob).hexdigest()
        report['sources'][str(path)]=tracked[path]
        return blob
    rtl=args.rtl.resolve()
    track(rtl)
    track(Path(__file__))
    tb=HERE/'orig_data_tb.sv'
    track(tb)
    parity=ROOT/'rtl/upli/upli_parity.v'
    track(parity)
    rtl_sources=[rtl,parity]
    if args.fault:
        fault=args.fault
        target=rtl
        code=rtl.read_text()
        before,after={
            'data_msb':('assign o_orig_data = i_data;',"assign o_orig_data = i_data ^ {1'b1,511'd0};"),
            'masked_parity':('^i_data[gen_group*64 +: 64]','^(i_data[gen_group*64 +: 64] & {64{i_byte_en[gen_group*8]}})'),
            'poison':('assign o_orig_data_error = i_error;',"assign o_orig_data_error = 1'b0;")}[fault]
        if fault=='masked_parity' and code.count(before)!=1:
            target=parity.resolve()
            code=target.read_text()
            before='^i_data[lane*64 +: 64]'
            after='^(i_data[lane*64 +: 64] & {64{i_byte_enable[lane]}})'
        if code.count(before)!=1:raise ValueError('isolated fault anchor must match once')
        mutant=stage/target.name
        mutant.write_text(code.replace(before,after))
        rtl_sources=[mutant if p.resolve()==target.resolve() else p for p in rtl_sources]
        report['fault']={'kind':fault,'original':str(target),'mutant':str(mutant),'sha256':hashlib.sha256(mutant.read_bytes()).hexdigest()}
    report['rows']=vectors(stage/'vectors.txt')
    def run(name,cmd,timeout=120):
        cmd=[str(x) for x in cmd]
        start=time.monotonic()
        with (stage/(name+'.log')).open('w') as log:
            try:rc=subprocess.run(cmd,cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=timeout).returncode
            except subprocess.TimeoutExpired:rc=124
        report['commands'][name]={'argv':cmd,'returncode':rc,'seconds':round(time.monotonic()-start,3)}
        return rc
    rc=run('compile',['iverilog','-g2012','-s','orig_data_tb','-o','sim.vvp',tb,*rtl_sources])
    if rc==0:run('simulate',['vvp','sim.vvp','+VECTORS=vectors.txt'])
    if rc==0 and not args.fault:
        run('g2001',['iverilog','-g2001','-s','upli_orig_data_channel','-o','elab.vvp',*rtl_sources])
        run('lint',['verilator','--lint-only','--language','1364-2001','-Wall','--top-module','upli_orig_data_channel',*rtl_sources])
        # Yosys quoted filenames preserve paths with spaces without shell interpolation.
        command='read_verilog '+' '.join(json.dumps(str(p)) for p in rtl_sources)+'; hierarchy -check -top upli_orig_data_channel; proc; opt; memory_map; opt; check -assert; stat; write_json netlist.json'
        run('yosys',['yosys','-Q','-T','-p',command])
    if args.integration and rc==0:
        sender_sources=[ROOT/'rtl/upli'/f'{n}.v' for n in ('upli_burst_sender','upli_burst_control','upli_credit_bank')]
        sender_tb=HERE/'sender_orig_data_tb.sv'
        generator=ROOT/'verification/rtl/burst_payload_vectors.py'
        for source in sender_sources+[sender_tb,generator]:track(source)
        # Hash oracle dependencies in place; no mirrored model/source tree is used.
        for source in (ROOT/'model/ualink').glob('*.py'):track(source)
        package=ROOT/'model/__init__.py'
        if package.exists():track(package)
        for ports in (1,2,4):
            cmd=[sys.executable,'-B',str(generator),'--ports',str(ports),'--request-width','184']
            start=time.monotonic()
            with (stage/f'p{ports}.vectors').open('w') as out,(stage/f'generate_p{ports}.log').open('w') as err:
                try:genrc=subprocess.run(cmd,cwd=stage,stdout=out,stderr=err,timeout=120).returncode
                except subprocess.TimeoutExpired:genrc=124
            report['commands'][f'generate_p{ports}']={'argv':cmd,'returncode':genrc,'seconds':round(time.monotonic()-start,3)}
            if genrc!=0:continue
            cmd=['iverilog','-g2012','-s','upli_burst_sender_tb',f'-Pupli_burst_sender_tb.C_NUM_PORTS={ports}','-Pupli_burst_sender_tb.C_REQUEST_WIDTH=184','-o',f'p{ports}.vvp',sender_tb,*rtl_sources,*sender_sources]
            if run(f'compile_p{ports}',cmd)==0:run(f'simulate_p{ports}',['vvp','-N',f'p{ports}.vvp',f'+VECTORS=p{ports}.vectors'])
    checks=report['commands']
    log=(stage/'simulate.log').read_text() if (stage/'simulate.log').exists() else ''
    passed=all(c['returncode']==0 for c in checks.values()) and 'ORIG_DATA_PASS' in log
    if args.integration:
        passed=passed and all(f'simulate_p{p}' in checks for p in (1,2,4))
        report['integration_counts']={}
        for p in (1,2,4):
            logfile=stage/f'simulate_p{p}.log'
            if not logfile.exists():continue
            log=logfile.read_text()
            count=len((stage/f'p{p}.vectors').read_text().splitlines())
            observed=re.search(r'PASS burst_payload rows=(\d+)',log)
            passed=passed and observed is not None and int(observed.group(1))==count
            report['integration_counts'][str(p)]={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',log)}
    if args.fault:passed=rc==0 and checks.get('simulate',{}).get('returncode')==1 and 'ORIG_COMPARE' in log
    report['changed_sources']=[str(p) for p,digest in tracked.items() if not p.exists() or hashlib.sha256(p.read_bytes()).hexdigest()!=digest]
    report['passed']=passed and not report['changed_sources']
    report['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
    (stage/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS' if report['passed'] else 'FAIL',stage/'result.json')
    return 0 if report['passed'] else 1

if __name__=='__main__':raise SystemExit(main())

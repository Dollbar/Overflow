"""Run: python3 verification/upli_channels/run_parity.py --label NEW [--faults] [--static].
Outputs fresh build/verification/upli_channels/parity/NEW snapshots, vectors, logs and hashes.
Next connect the parity groups to typed native channels; this check is not RAS recovery.
"""
import argparse
import hashlib
import json
from pathlib import Path
import random
import re
import subprocess

ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())

def oracle(kind,fields,received):
    enabled,valid,control,address,auth,data,be,cv,cp,vc,num=fields
    bit=lambda value: value.bit_count()%2
    width=(68,48,42,9)[kind]
    parity=valid | (bit(control & ((1<<width)-1))<<1)
    if kind==0:parity|=bit(address)<<2
    if kind!=3:parity|=bit(auth)<<3
    if kind in (1,3):
        for lane in range(8):parity|=bit((data>>(64*lane))&((1<<64)-1))<<(4+lane)
    if kind==3:parity|=bit(be)<<12
    parity|=bit(cv)<<13
    parity|=bit(cp | (vc<<4) | (num<<12))<<14
    checked=(1<<0)|(1<<13)
    if valid:
        checked|=1<<1
        if kind==0:checked|=1<<2
        if kind!=3:checked|=1<<3
        if kind in (1,3):checked|=255<<4
        if kind==3:checked|=1<<12
    if cv:checked|=1<<14
    errors=(parity^received)&checked if enabled else 0
    return parity,errors,int(bool(errors&0x6007)),int(bool(errors&0x1ff0)),int(bool(errors&8))

def vectors(kind):
    rng=random.Random(68100+kind)
    widths=(1,1,68,57,64,512,64,4,4,8,8)
    base=[1,1]+[(1<<w)-1 for w in widths[2:]]
    samples=[]
    # Flip every protected/unused input bit against an independent uncorrupted parity.
    for field,width in enumerate(widths):
        for b in range(width):
            f=base.copy();f[field]^=1<<b
            received=oracle(kind,base,0)[0]
            samples.append(f+[received]+list(oracle(kind,f,received)))
    for valid in (0,1):
        for cv in range(16):
            f=[1,valid]+[rng.getrandbits(w) for w in widths[2:]];f[7]=cv
            good=oracle(kind,f,0)[0]
            for b in range(15):
                received=good^(1<<b)
                samples.append(f+[received]+list(oracle(kind,f,received)))
    for _ in range(500):
        f=[rng.getrandbits(w) for w in widths];received=rng.getrandbits(15)
        samples.append(f+[received]+list(oracle(kind,f,received)))
    return samples

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rtl',type=Path,default=ROOT/'rtl/upli/upli_parity.v');p.add_argument('--label',required=True);p.add_argument('--faults',action='store_true');p.add_argument('--static',action='store_true')
    a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
    stage=ROOT/'build/verification/upli_channels/parity'/a.label;stage.mkdir(parents=True,exist_ok=False)
    source=a.rtl.resolve();blob=source.read_text()
    (stage/'original.v').write_text(blob);(stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    tb=Path(__file__).with_name('parity_tb.sv');(stage/'parity_tb.sv').write_bytes(tb.read_bytes())
    cases=[(k,None) for k in range(4)]
    if a.faults:cases += [(0,'idle_valid'),(3,'masked_data'),(1,'credit_mask'),(3,'byte_class')]
    mutations={
        'idle_valid':("checked[0] = 1'b1;","checked[0] = i_valid;"),
        'masked_data':('^i_data[lane*64 +: 64]','^(i_data[lane*64 +: 64] & {64{i_byte_enable[lane]}})'),
        'credit_mask':('^{i_credit_pool,i_credit_vc,i_credit_num}','^{i_credit_pool & i_credit_valid,i_credit_vc,i_credit_num}'),
        'byte_class':('o_errors[12:4]','o_errors[11:4]')}
    result={'passed':True,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'cases':[]}
    for kind,fault in cases:
        folder=stage/f'k{kind}_{fault or "normal"}';folder.mkdir();code=blob
        if fault:
            before,after=mutations[fault]
            if code.count(before)!=1:raise ValueError('mutation anchor changed: '+fault)
            code=code.replace(before,after)
        (folder/'upli_parity.v').write_text(code);rows=vectors(kind)
        (folder/'vectors.txt').write_text(''.join(' '.join(format(v,'x') for v in row)+'\n' for row in rows))
        cmds={'compile':['iverilog','-g2012','-s','tb',f'-Ptb.KIND={kind}','-o','sim.vvp','upli_parity.v',str(stage/'parity_tb.sv')],'run':['vvp','sim.vvp']}
        if a.static and not fault:
            cmds['g2001']=['iverilog','-g2001','-s','upli_parity',f'-Pupli_parity.CHANNEL_KIND={kind}','-o','syntax.vvp','upli_parity.v']
            cmds['lint']=['verilator','--lint-only','-Wall','--language','1364-2001','--top-module','upli_parity',f'-GCHANNEL_KIND={kind}','upli_parity.v']
            cmds['yosys']=['yosys','-Q','-T','-p',f'read_verilog upli_parity.v; chparam -set CHANNEL_KIND {kind} upli_parity; hierarchy -check -top upli_parity; proc; opt; check -assert; stat']
        row={'kind':kind,'fault':fault,'vectors':len(rows),'commands':cmds,'exit':{}}
        for name,cmd in cmds.items():
            with (folder/(name+'.log')).open('w') as log:
                try:rc=subprocess.run(cmd,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=90).returncode
                except subprocess.TimeoutExpired:rc=124
            row['exit'][name]=rc
            if name=='compile' and rc:break
        log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
        row['passed']=row['exit'].get('compile')==0 and row['exit'].get('run')==(1 if fault else 0) and ('PARITY_MISMATCH' if fault else 'PARITY_PASS') in log
        row['passed'] &= all(v==0 for k,v in row['exit'].items() if k!='run')
        result['passed'] &= row['passed'];result['cases'].append(row);print(kind,fault,row['exit'],row['passed'])
    result['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
    (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

#!/usr/bin/env python3
"""Compare installed typed leaves against frozen independent original XOR fixtures.
Run: python3 verification/upli_channels/run_shared_parity.py --label NEW
Outputs: build/verification/upli_channels/shared_parity/NEW source snapshots, hashes,
hierarchy JSON, SAT logs/counterexamples, g2001 and strict Verilator logs.
Next: inspect result.json; compilation requires the common upli_parity primitive.
This is full combinational two-state equivalence, not the stateful UPLI sender test.
"""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
MODULES={'request':'upli_request_channel','orig':'upli_orig_data_channel'}
def call(command,folder,name):
    with (folder/(name+'.log')).open('w') as log:
        try:code=subprocess.run(command,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=120).returncode
        except subprocess.TimeoutExpired:code=124
    return {'command':command,'exit':code}

def prove(folder,kind,gold,gate,parity):
    name=MODULES[kind]
    (folder/'gold.v').write_bytes(gold.replace(('module '+name).encode(),b'module gold',1))
    (folder/'gate.v').write_bytes(gate.replace(('module '+name).encode(),b'module gate',1))
    (folder/'upli_parity.v').write_bytes(parity)
    script='''read_verilog gold.v gate.v upli_parity.v
miter -equiv -make_assert -make_outputs gold gate miter
hierarchy -check -top miter
proc
write_json hierarchy.json
flatten
opt_clean
check -assert
sat -verify -prove-asserts -set-def-inputs -show-inputs -show-outputs -dump_json witness.json -dump_vcd witness.vcd
'''
    (folder/'proof.ys').write_text(script)
    result=call(['yosys','-Q','-T','-s','proof.ys'],folder,'proof')
    log=(folder/'proof.log').read_text();result['equivalent']=result['exit']==0 and 'SAT proof finished - no model found: SUCCESS!' in log
    result['counterexample']=result['exit']==1 and 'proof did fail' in log and (folder/'witness.json').exists()
    return result

def inspect_hierarchy(folder,kind):
    modules=json.loads((folder/'hierarchy.json').read_text())['modules'];leaf=modules['gate'];cells=leaf['cells']
    parity=[cell for cell in cells.values() if 'upli_parity' in cell['type']]
    if len(parity)!=1:raise AssertionError('exactly one actual primitive is required')
    if any(cell['type']=='$reduce_xor' for cell in cells.values()):raise AssertionError('duplicate leaf XOR remains')
    groups=parity[0]['connections']['o_parity']
    mapping={'o_valid_parity':[0],'o_control_parity':[1],'o_address_parity':[2],'o_auth_tag_parity':[3]} if kind=='request' else {'o_orig_data_valid_parity':[0],'o_orig_data_fields_parity':[1],'o_orig_data_parity':list(range(4,12)),'o_orig_data_byte_en_parity':[12]}
    for name,positions in mapping.items():
        if leaf['ports'][name]['bits']!=[groups[index] for index in positions]:raise AssertionError('primitive output not directly connected: '+name)
    return {'primitive_count':len(parity),'primitive_type':parity[0]['type'],'direct_output_groups':mapping,'leaf_reduce_xor_count':0,'input_bits':sum(len(p['bits']) for p in leaf['ports'].values() if p['direction']=='input'),'compared_output_bits':sum(len(p['bits']) for p in leaf['ports'].values() if p['direction']=='output')}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label',required=True)
    args=parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',args.label):parser.error('safe fresh label required')
    out=ROOT/'build/verification/upli_channels/shared_parity'/args.label
    out.mkdir(parents=True,exist_ok=False)
    blobs={name:(ROOT/'rtl/upli'/(name+'.v')).read_bytes() for name in list(MODULES.values())+['upli_parity']}
    gold={kind:(HERE/'fixtures'/(name+'_xor.v')).read_bytes() for kind,name in MODULES.items()}
    primitive=blobs['upli_parity']
    (out/'runner.py').write_bytes(Path(__file__).read_bytes())
    for name,blob in blobs.items():(out/(name+'.v')).write_bytes(blob)
    for kind,blob in gold.items():(out/(MODULES[kind]+'_xor.v')).write_bytes(blob)
    result={'passed':True,'cases':{},'source_sha256':{name:hashlib.sha256(blob).hexdigest() for name,blob in blobs.items()},'reference_sha256':{kind:hashlib.sha256(blob).hexdigest() for kind,blob in gold.items()}}
    for kind,name in MODULES.items():
        folder=out/kind;folder.mkdir()
        check=prove(folder,kind,gold[kind],blobs[name],primitive)
        check['hierarchy']=inspect_hierarchy(folder,kind)
        (folder/(name+'.v')).write_bytes(blobs[name])
        check['g2001']=call(['iverilog','-g2001','-s',name,'-o','rtl.vvp',name+'.v','upli_parity.v'],folder,'g2001')
        check['strictlint']=call(['verilator','--lint-only','--Wall','--language','1364-2001','--top-module',name,name+'.v','upli_parity.v'],folder,'strictlint')
        check['passed']=check['equivalent'] and check['g2001']['exit']==0 and check['strictlint']['exit']==0
        result['cases'][kind]=check;result['passed']&=check['passed']
    tag=blobs['upli_request_channel']
    bad_tag=tag.replace(b'.i_control({o_tag, o_length',b".i_control({1'b0, o_tag[9:0], o_length")
    orig=blobs['upli_orig_data_channel']
    bad_data=orig.replace(b'.i_data(o_orig_data)',b'.i_data(faulty_masked_data)')
    helper=b"""    wire [511:0] faulty_masked_data;
    genvar masked_byte;
    generate for(masked_byte=0;masked_byte<64;masked_byte=masked_byte+1)begin:bad_mask
        assign faulty_masked_data[masked_byte*8+:8]=o_orig_data[masked_byte*8+:8]&{8{o_orig_data_byte_en[masked_byte]}};
    end endgenerate
"""
    bad_data=bad_data.replace(b'    upli_parity #',helper+b'    upli_parity #',1)
    if bad_tag==tag or bad_data==orig:raise AssertionError('actual fault anchor missing')
    for case,kind,blob in [('tag_high_fault','request',bad_tag),('be_mask_fault','orig',bad_data)]:
        folder=out/case;folder.mkdir()
        check=prove(folder,kind,gold[kind],blob,primitive)
        check['passed']=check['counterexample']
        result['cases'][case]=check;result['passed']&=check['passed']
    result['artifacts_sha256']={str(p.relative_to(out)):hashlib.sha256(p.read_bytes()).hexdigest() for p in out.rglob('*') if p.is_file()}
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result['cases']))
    return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

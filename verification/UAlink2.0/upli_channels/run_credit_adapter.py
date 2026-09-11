#!/usr/bin/env python3
"""Run independent credit parity and actual receive-channel return checks.
Run: python3 verification/upli_channels/run_credit_adapter.py --label NEW
Add --integration --kd28-root /authorized/checkout for actual receive SRAM tests.
Outputs: build/verification/upli_channels/credit_adapter/NEW source snapshots,
independent vectors, command/log/return codes and result.json with source hashes.
Next inspect diagnostics separately from credit, connection and recovery policy.
"""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
from credit_adapter_reference import vectors
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
HERE=Path(__file__).resolve().parent
MODULES=('upli_credit_guard','upli_credit_return_adapter','upli_parity')
def run(command,folder,name):
    with (folder/(name+'.log')).open('w') as log:
        try:code=subprocess.run(command,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=120).returncode
        except subprocess.TimeoutExpired:code=124
    return {'command':command,'exit':code}
def integration(a,out,sources):
    (out/'credit_adapter_receive_tb.sv').write_bytes((HERE/'credit_adapter_receive_tb.sv').read_bytes())
    manifest_path=a.project_root/'third_party/kd28_dependency.json'
    manifest_blob=manifest_path.read_bytes();manifest=json.loads(manifest_blob)
    (out/'kd28_dependency.json').write_bytes(manifest_blob)
    external=[];external_hashes={}
    for rel,expected_hash in manifest['functional_sources_sha256'].items():
        path=(a.kd28_root/rel).resolve();actual=hashlib.sha256(path.read_bytes()).hexdigest()
        if actual!=expected_hash:raise AssertionError('external dependency hash changed: '+str(path))
        external.append(str(path));external_hashes[str(path)]=actual
    local=[]
    for name in ('upli_receive_fifo','upli_receive_storage','upli_credit_initializer','upli_credit_return_queue','upli_credit_bank','upli_receive_channel'):
        blob=(a.project_root/'rtl/upli'/(name+'.v')).read_bytes()
        (out/(name+'.v')).write_bytes(blob);local.append(name+'.v')
    compile_result=run(['iverilog','-g2012','-s','credit_adapter_receive_tb','-Pcredit_adapter_receive_tb.PORTS='+str(a.ports),'-o','receive.vvp',*sources,*local,*external,'credit_adapter_receive_tb.sv'],out,'receive_compile')
    sim=run(['vvp','receive.vvp'],out,'receive_run') if compile_result['exit']==0 else {'exit':None}
    log=(out/'receive_run.log').read_text() if (out/'receive_run.log').exists() else ''
    if a.fault:
        passed=compile_result['exit']==0 and sim['exit']==1 and any(marker in log for marker in ('CREDIT_RETURN_DIRECT','CREDIT_RETURN_PARITY','CREDIT_RETURN_GUARD'))
    else:passed=compile_result['exit']==0 and sim['exit']==0 and 'CREDIT_RETURN_PASS' in log
    unchanged=all(hashlib.sha256(Path(path).read_bytes()).hexdigest()==h for path,h in external_hashes.items())
    return {'passed':passed and unchanged,'ports':a.ports,'compile':compile_result,'run':sim,'external_sha256':external_hashes,'external_unchanged':unchanged}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--label',required=True)
    p.add_argument('--rtl-dir',type=Path,default=ROOT/'rtl/upli')
    p.add_argument('--project-root',type=Path,default=ROOT)
    p.add_argument('--red',choices=('guard','adapter'))
    p.add_argument('--fault',choices=('guard_valid','guard_mask','adapter_init','adapter_gate'))
    p.add_argument('--integration',action='store_true')
    p.add_argument('--ports',type=int,choices=(1,2,4),default=4)
    p.add_argument('--kd28-root',type=Path)
    a=p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
    if a.integration and not a.kd28_root:p.error('integration requires explicit --kd28-root')
    if a.red and (a.integration or a.fault):p.error('red isolates the local pre-implementation capability stub')
    out=ROOT/'build/verification/upli_channels/credit_adapter'/a.label;out.mkdir(parents=True,exist_ok=False)
    blobs={name:(a.rtl_dir/(name+'.v')).read_bytes() for name in MODULES}
    for name,blob in blobs.items():(out/(name+'_healthy.v')).write_bytes(blob)
    mutations={
      'guard_valid':('upli_credit_guard',b'.i_check_enable(i_check_enable)',b'.i_check_enable(i_check_enable && (|i_credit_valid))'),
      'guard_mask':('upli_credit_guard',b'.i_credit_pool(i_credit_pool)',b'.i_credit_pool(i_credit_pool & i_credit_valid)'),
      'adapter_init':('upli_credit_return_adapter',b'.i_credit_pool(o_credit_pool)',b'.i_credit_pool(o_credit_pool ^ o_credit_init_done)'),
      'adapter_gate':('upli_credit_return_adapter',b'assign o_credit_valid = i_credit_valid;',b'assign o_credit_valid = i_credit_valid & i_credit_init_done;')}
    if a.fault:
        name,before,after=mutations[a.fault]
        if blobs[name].count(before)!=1:raise AssertionError('actual mutation anchor must be unique')
        blobs[name]=blobs[name].replace(before,after,1)
    for name,blob in blobs.items():(out/(name+'.v')).write_bytes(blob)
    for name in ('run_credit_adapter.py','credit_adapter_reference.py','credit_adapter_tb.sv'):(out/name).write_bytes((HERE/name).read_bytes())
    rows=vectors();(out/'vectors.txt').write_text(''.join(' '.join(format(v,'x') for v in row)+'\n' for row in rows))
    sources=[name+'.v' for name in MODULES]
    c=run(['iverilog','-g2012','-s','credit_adapter_tb','-Pcredit_adapter_tb.TEST_GUARD='+str(int(a.red!='adapter')),'-Pcredit_adapter_tb.TEST_ADAPTER='+str(int(a.red!='guard')),'-o','sim.vvp',*sources,'credit_adapter_tb.sv'],out,'compile')
    sim=run(['vvp','sim.vvp'],out,'run') if c['exit']==0 else {'exit':None}
    log=(out/'run.log').read_text() if (out/'run.log').exists() else ''
    negative=bool(a.red or a.fault)
    passed=c['exit']==0 and ((sim['exit']==1 and ('CREDIT_GUARD_COMPARE' in log or 'CREDIT_ADAPTER_COMPARE' in log)) if negative else (sim['exit']==0 and 'CREDIT_ADAPTER_PASS' in log))
    result={'passed':passed,'vectors':len(rows),'red':a.red,'fault':a.fault,'compile':c,'run':sim,'static':{}}
    if not negative:
      for name in MODULES[:2]:
        cmds={'g2001':['iverilog','-g2001','-s',name,'-o',name+'.vvp',*sources],
              'strictlint':['verilator','--lint-only','--Wall','--language','1364-2001','--top-module',name,*sources],
              'yosys':['yosys','-Q','-T','-p','read_verilog '+' '.join(sources)+'; hierarchy -check -top '+name+'; proc; check -assert; write_json '+name+'.json']}
        result['static'][name]={key:run(command,out,name+'_'+key) for key,command in cmds.items()}
        result['passed']&=all(v['exit']==0 for v in result['static'][name].values())
        if result['static'][name]['yosys']['exit']==0:
          design=json.loads((out/(name+'.json')).read_text())['modules'][name]
          cells=list(design['cells'].values());primitive=[cell for cell in cells if 'upli_parity' in cell['type']]
          structural={'primitive_count':len(primitive),'leaf_reduce_xor_count':sum(cell['type']=='$reduce_xor' for cell in cells),'sequential_cells':sum(any(x in cell['type'].lower() for x in ('dff','latch','mem')) for cell in cells)}
          if len(primitive)==1:
            con=primitive[0]['connections']
            structural['noncredit_inputs_zero']=all(all(b=='0' for b in con[port]) for port in ('i_valid','i_control','i_address','i_auth','i_data','i_byte_enable'))
            structural['received_noncredit_zero']=all(b=='0' for b in con['i_received_parity'][:13])
            port=design['ports']
            if name=='upli_credit_guard':
                structural['direct_credit_groups']=port['o_valid_error']['bits']==con['o_errors'][13:14] and port['o_control_error']['bits']==con['o_errors'][14:15]
            else:
                structural['direct_credit_groups']=port['o_credit_valid_parity']['bits']==con['o_parity'][13:14] and port['o_credit_parity']['bits']==con['o_parity'][14:15]
                structural['direct_credit_groups']&=all(port['i_credit_'+field]['bits']==port['o_credit_'+field]['bits'] for field in ('valid','pool','vc','num','init_done'))
          structural['passed']=structural['primitive_count']==1 and structural['leaf_reduce_xor_count']==0 and structural['sequential_cells']==0 and structural.get('noncredit_inputs_zero') and structural.get('received_noncredit_zero') and structural.get('direct_credit_groups')
          result['static'][name]['structure']=structural;result['passed']&=bool(structural['passed'])
    if a.integration:
        result['integration']=integration(a,out,sources)
        result['passed']&=result['integration']['passed']
    result['sources_sha256']={name:hashlib.sha256((out/(name+'.v')).read_bytes()).hexdigest() for name in MODULES}
    result['healthy_sources_sha256']={name:hashlib.sha256((out/(name+'_healthy.v')).read_bytes()).hexdigest() for name in MODULES}
    result['artifacts_sha256']={str(f.relative_to(out)):hashlib.sha256(f.read_bytes()).hexdigest() for f in out.rglob('*') if f.is_file()}
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='artifacts_sha256'}));return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

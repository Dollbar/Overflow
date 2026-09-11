#!/usr/bin/env python3
"""Run real Endpoint/Switch causal Read transactions without response fixtures.
Run: python3 verification/endpoint_transaction/run_transactions.py --kd28-root PATH --label NEW [--inject] [--bank-depth N]
Outputs source snapshots, command/return-code logs and result.json in build/verification/endpoint_transaction/NEW.
Next inspect actual request, memory-result, response and completion ownership before expanding profiles.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASELINE = '''module tb; parameter INJECT=0, BANK_DEPTH=3;
reg clk=0; always #5 clk=~clk;
reg rstn=0; wire ready,implemented;
endpoint_transaction_core dut(.i_clk(clk),.i_rstn(rstn),.i_enable(1'b1),.i_valid(1'b1),
.i_data(512'd0),.i_meta(128'd0),.o_ready(ready),.o_implemented(implemented));
initial begin #12;rstn=1;#20;if(!ready||!implemented)$fatal(1,"UNIMPLEMENTED_TRANSACTION_CORE");$finish;end
endmodule
'''

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--label',required=True);p.add_argument('--kd28-root',type=Path)
    p.add_argument('--inject',action='store_true');p.add_argument('--bank-depth',type=int,default=3)
    p.add_argument('--shell-baseline',action='store_true');p.add_argument('--fault',choices=['data_half','retirement','tag_high'])
    a=p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',a.label):p.error('safe new label required')
    if not 1<=a.bank_depth<=16:p.error('bank-depth must be 1..16')
    stage=ROOT/'build/verification/endpoint_transaction'/a.label;stage.mkdir(parents=True,exist_ok=False)
    srcdir=stage/'rtl';srcdir.mkdir()
    if a.shell_baseline:
        sources=[ROOT/'rtl/endpoint/endpoint_transaction_core.v'];tb=BASELINE
    else:
        if a.kd28_root is None:p.error('explicit --kd28-root required')
        dep=a.kd28_root.resolve();manifest=json.loads((ROOT/'third_party/kd28_dependency.json').read_text())
        dependencies=[]
        for rel,h in manifest['functional_sources_sha256'].items():
            path=dep/rel
            if hashlib.sha256(path.read_bytes()).hexdigest()!=h:raise ValueError('dependency hash mismatch: '+rel)
            dependencies.append(path)
        sources=sorted((ROOT/'rtl').rglob('*.v'))+dependencies
        tb=(ROOT/'verification/endpoint_transaction/transactions_tb.sv').read_text()
    copies=[];hashes={}
    for index,path in enumerate(sources):
        dest=srcdir/(str(index)+'_'+path.name);shutil.copyfile(path,dest);copies.append(dest)
        mutations={
            'data_half':('endpoint_transaction_core.v', 'assign o_data1={completer_data[511:256],256\'d0};', 'assign o_data1={256\'d0,256\'d0};'),
            'retirement':('ualink_endpoint_top.v', '.i_read_ready(selected_read_ready),.o_read_valid(o_read_valid)', '.i_read_ready(1\'b1),.o_read_valid(o_read_valid)'),
            'tag_high':('endpoint_transaction_core.v', '.i_response_tag(response_tag)', '.i_response_tag({1\'b0,response_tag[9:0]})')}
        if a.fault and path.name==mutations[a.fault][0]:
            _,before,after=mutations[a.fault];text=dest.read_text()
            if text.count(before)!=1:raise ValueError('fault anchor missing/ambiguous')
            dest.write_text(text.replace(before,after))
        hashes[str(path)]=hashlib.sha256(path.read_bytes()).hexdigest()
    for path in [Path(__file__),ROOT/'config/ip_module_inventory.json']+([] if a.shell_baseline else [ROOT/'verification/endpoint_transaction/transactions_tb.sv']):
        hashes[str(path)]=hashlib.sha256(path.read_bytes()).hexdigest()
    (stage/'tb.sv').write_text(tb)
    command=['iverilog','-g2012','-s','tb',f'-Ptb.INJECT={int(a.inject)}',f'-Ptb.BANK_DEPTH={a.bank_depth}',
             '-o',str(stage/'sim.vvp'),str(stage/'tb.sv'),*map(str,copies)]
    result=dict(passed=False,shell_baseline=a.shell_baseline,inject=a.inject,bank_depth=a.bank_depth,
                fault=a.fault,scope='actual causal single64B Read RTL; local DL record and explicit CRC status, not standard framing',sources=hashes)
    for name,cmd in [('compile',command),('run',['vvp',str(stage/'sim.vvp')])]:
        result[name+'_command']=cmd
        with (stage/(name+'.log')).open('w') as log:
            try:code=subprocess.run(cmd,cwd=stage,stdout=log,stderr=subprocess.STDOUT,timeout=180).returncode
            except subprocess.TimeoutExpired:code=124
        result[name+'_exit']=code
        if code and name=='compile':break
    log=(stage/'run.log').read_text() if (stage/'run.log').exists() else ''
    result['passed']=(result.get('compile_exit')==0 and result.get('run_exit')==1 and 'UNIMPLEMENTED_TRANSACTION_CORE' in log) if a.shell_baseline else (result.get('run_exit')==0 and 'CAUSAL_READ_PASS' in log)
    if a.fault:
        result['passed']=result.get('compile_exit')==0 and result.get('run_exit')==1 and any(x in log for x in {'data_half':['CAUSAL_COMPLETION_DATA'],'tag_high':['CAUSAL_DUT_ERROR'],'retirement':['CAUSAL_DUT_ERROR','CAUSAL_TIMEOUT','CAUSAL_COMPLETION_DATA']}[a.fault])
    result['artifacts_sha256']={str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}
    (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k in ('passed','shell_baseline','compile_exit','run_exit')}))
    return 0 if result['passed'] else 1

if __name__=='__main__':raise SystemExit(main())

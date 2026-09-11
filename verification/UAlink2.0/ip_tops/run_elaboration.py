"""Elaborate both development IP tops using the explicit SRAM macro boundary.
Run: python3 verification/ip_tops/run_elaboration.py --kd28-root PATH --label NEW
Add --transactions for the Read core, or --writes for mixed ordinary Write/Read; add --synth for generic gate synthesis (no technology mapping or STA).
Outputs scripts, source hashes, Yosys logs/graphs under build/verification/ip_tops/NEW.
Next review pending module states and run the actual behavioral ESE regression.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True)
    p.add_argument('--label',required=True);p.add_argument('--synth',action='store_true');p.add_argument('--transactions',action='store_true');p.add_argument('--writes',action='store_true')
    p.add_argument('--originator-capacity',type=int,default=4);p.add_argument('--completer-capacity',type=int,default=4);a=p.parse_args()
    a.transactions=a.transactions or a.writes
    if not 1<=a.originator_capacity<=255 or not 1<=a.completer_capacity<=4:p.error('legal originator 1..255 and completer 1..4 capacities required')
    if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('new safe label required')
    stage=ROOT/'build/verification/ip_tops'/a.label;stage.mkdir(parents=True,exist_ok=False)
    dep=a.kd28_root.resolve()/'Library/models/kd28'
    sources=sorted((ROOT/'rtl').rglob('*.v'))+[dep/'fifo/rtl/kd28_fifo_sdp_storage_map.v',dep/'sram/rtl/kd28_sram_blackboxes.v']
    result=dict(complete=False,endpoint_transaction_mode=int(a.transactions),endpoint_write_enable=int(a.writes),originator_capacity=a.originator_capacity,completer_capacity=a.completer_capacity,mode='generic_synthesis' if a.synth else 'elaboration',technology_sta=False,functional_completeness=False,sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources},results=[])
    for top in ('ualink_endpoint_top','ualink_switch_top'):
        folder=stage/top;folder.mkdir()
        command='read_verilog '+' '.join('"'+str(f)+'"' for f in sources)+'\n'
        if a.transactions and top=='ualink_endpoint_top':command+=f'chparam -set TRANSACTION_MODE 1 -set ORIGINATOR_CAPACITY {a.originator_capacity} -set COMPLETER_CAPACITY {a.completer_capacity} -set WRITE_ENABLE {int(a.writes)} ualink_endpoint_top\n'
        command+=f'hierarchy -check -top {top}\n'
        command+=f'synth -top {top} -noabc\n' if a.synth else 'proc\nopt\n'
        command+=f'check -assert\nstat\nwrite_json "{folder}/design.json"\n'
        (folder/'run.ys').write_text(command)
        with (folder/'run.log').open('w') as log:
            try:code=subprocess.run(['yosys','-Q','-T','-s',str(folder/'run.ys')],stdout=log,stderr=subprocess.STDOUT,cwd=ROOT,timeout=240).returncode
            except subprocess.TimeoutExpired:code=124
        row=dict(top=top,exit=code,passed=code==0)
        if code==0:
            graph=json.loads((folder/'design.json').read_text())
            row.update(modules=len(graph['modules']),cells=sum(len(m.get('cells',{})) for m in graph['modules'].values()),macro_blackboxes=sorted(n for n,m in graph['modules'].items() if m.get('attributes',{}).get('blackbox')))
        result['results'].append(row);print(row,flush=True)
        (stage/'results.json').write_text(json.dumps(result,indent=2)+'\n')
    result['complete']=all(r['passed'] for r in result['results']);(stage/'results.json').write_text(json.dumps(result,indent=2)+'\n')
    return 0 if result['complete'] else 1


if __name__=='__main__':raise SystemExit(main())

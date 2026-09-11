"""Elaborate both development IP tops using the explicit SRAM macro boundary.
Run: python3 verification/ip_tops/run_elaboration.py --kd28-root PATH --label NEW
Add --synth for generic gate synthesis (no technology mapping or STA).
Outputs scripts, source hashes, Yosys logs/graphs under build/verification/ip_tops/NEW.
Next review pending module states and run the actual behavioral ESE regression.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

ROOT=Path(__file__).resolve().parents[2]


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True)
    p.add_argument('--label',required=True);p.add_argument('--synth',action='store_true');a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('new safe label required')
    stage=ROOT/'build/verification/ip_tops'/a.label;stage.mkdir(parents=True,exist_ok=False)
    dep=a.kd28_root.resolve()/'Library/models/kd28'
    sources=sorted((ROOT/'rtl').rglob('*.v'))+[dep/'fifo/rtl/kd28_fifo_sdp_storage_map.v',dep/'sram/rtl/kd28_sram_blackboxes.v']
    result=dict(complete=False,mode='generic_synthesis' if a.synth else 'elaboration',technology_sta=False,functional_completeness=False,sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources},results=[])
    for top in ('ualink_endpoint_top','ualink_switch_top'):
        folder=stage/top;folder.mkdir()
        command='read_verilog '+' '.join('"'+str(f)+'"' for f in sources)+'\n'
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

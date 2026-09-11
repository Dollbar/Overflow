#!/usr/bin/env python3
"""Actual switch top route configuration regression.
Run: python3 verification/ip_tops/run_switch_top_config.py --label NEW --faults
Outputs: build/verification/ip_tops/switch_top_config/NEW source snapshots, simulator logs and SHA256 manifest.
Next: promote the test only after reviewing actual production top results.
"""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
HERE=Path(__file__).resolve().parent

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--label',required=True);p.add_argument('--faults',action='store_true');a=p.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',a.label):p.error('safe fresh label required')
    stage=ROOT/'build/verification/ip_tops/switch_top_config'/a.label;stage.mkdir(parents=True,exist_ok=False)
    blobs={str(f.relative_to(ROOT)):f.read_bytes() for f in sorted((ROOT/'rtl').rglob('*.v'))}
    for name,blob in blobs.items():
        target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(blob)
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes());(stage/'tb.sv').write_bytes((HERE/'switch_top_config_tb.sv').read_bytes())
    cases=[(ports,mode,None) for ports in (1,3,4,5) for mode in (0,1)]
    if a.faults:cases +=[(3,1,'quiescence_owner'),(3,1,'active_route_bypass')]
    results=[]
    for ports,mode,fault in cases:
        name=f'p{ports}_cfg{mode}'+('_'+fault if fault else '');folder=stage/name;folder.mkdir()
        sources=[str((stage/path).resolve()) for path in blobs]
        if fault:
            old,new={
                'quiescence_owner':('rstn && !(|packet_owned) && !(|i_valid)','rstn && !(|i_valid)'),
                'active_route_bypass':('.i_route_ids(active_route_ids),','.i_route_ids(i_route_ids),'),
            }[fault]
            top=blobs['rtl/switch/ualink_switch_top.v'].decode()
            if top.count(old)!=1:raise ValueError('missing or ambiguous fault anchor '+fault)
            altered=folder/'ualink_switch_top.v';altered.write_text(top.replace(old,new));sources=[str(altered.resolve()) if s.endswith('/rtl/switch/ualink_switch_top.v') else s for s in sources]
        item={'name':name,'ports':ports,'config':mode,'fault':fault}
        for phase,cmd in [('compile',['iverilog','-g2012','-s','tb',f'-Ptb.PORTS={ports}',f'-Ptb.CONFIG={mode}','-o','sim.vvp',*sources,str((stage/'tb.sv').resolve())]),('run',['vvp','sim.vvp'])]:
            with (folder/(phase+'.log')).open('w') as log:
                try:code=subprocess.run(cmd,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=60).returncode
                except subprocess.TimeoutExpired:code=124
            item[phase]={'command':cmd,'exit':code}
            if phase=='compile' and code:break
        log=(folder/'run.log').read_text() if (folder/'run.log').exists() else ''
        item['passed']=item['compile']['exit']==0 and item.get('run',{}).get('exit')==(1 if fault else 0) and ('CONFIG_MISMATCH' if fault else 'CONFIG_PASS') in log
        results.append(item);print(name,item['passed'],log.strip(),flush=True)
    result={'passed':all(c['passed'] for c in results),'cases':results,'source_sha256':{n:hashlib.sha256(b).hexdigest() for n,b in blobs.items()},'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}}
    (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

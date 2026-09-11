#!/usr/bin/env python3
"""Run: python3 verification/upli_channels/run_receive_tdm.py --label NEW [--rtl PATH] [--faults].
Outputs: ROOT/build/verification/upli_channels/receive_tdm/NEW snapshots, vectors, logs, hashes.
Use --station --kd28-root PATH for real station/four-SRAM integration.
Next: connect actual native RX fields; this observer does not control traffic or recover faults.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
from receive_tdm_reference import generate
ROOT=(lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
HERE=Path(__file__).resolve().parent

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label',required=True)
    parser.add_argument('--rtl',type=Path,default=ROOT/'rtl/upli/upli_receive_tdm_monitor.v')
    parser.add_argument('--ports',type=int,choices=(1,2,4))
    parser.add_argument('--faults',action='store_true')
    parser.add_argument('--station',action='store_true',help='also observe actual station TX and four SRAM receive chains')
    parser.add_argument('--kd28-root',type=Path)
    parser.add_argument('--station-root',type=Path,default=ROOT,help='explicit dependency project root for candidate migration tests')
    args=parser.parse_args()
    if not re.fullmatch('[A-Za-z0-9_-]+',args.label):parser.error('safe fresh label required')
    if args.station and not args.kd28_root:parser.error('--station needs explicit --kd28-root')
    stage=ROOT/'build/verification/upli_channels/receive_tdm'/args.label
    stage.mkdir(parents=True,exist_ok=False)
    source=stage/'source';source.mkdir()
    hashes={}
    for path in [args.rtl.resolve(),HERE/'receive_tdm_tb.sv',HERE/'receive_tdm_reference.py',HERE/'receive_tdm_station_tb.sv',Path(__file__)]:
        if path.exists():
            blob=path.read_bytes();(source/path.name).write_bytes(blob);hashes[str(path)]=hashlib.sha256(blob).hexdigest()
    cases=[]
    def run(folder,name,command):
        start=time.monotonic()
        with (folder/(name+'.log')).open('w') as log:
            try:code=subprocess.run([str(c) for c in command],cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=60).returncode
            except subprocess.TimeoutExpired:code=124
        return {'command':[str(c) for c in command],'returncode':code,'seconds':round(time.monotonic()-start,3)}
    rtl=source/'upli_receive_tdm_monitor.v'
    mutations={'phase':("reg_phase <= next_phase;","reg_phase <= observed_port;"),
               'idle':('else if (reg_known) reg_phase <= next_phase;','else if (reg_known && observed_valid) reg_phase <= next_phase;'),
               'crosschannel':('assign channel_port = i_rd_port;', 'assign channel_port = i_req_port;')}
    for ports in ([args.ports] if args.ports else [1,2,4]):
        for fault in ([None,'phase','idle','crosschannel'] if args.faults and ports==4 else [None]):
            folder=stage/(f'p{ports}'+('_'+fault if fault else ''));folder.mkdir()
            target=rtl
            if fault:
                code=rtl.read_text()
                old,new=mutations[fault]
                if old not in code:raise ValueError('missing mutation anchor '+fault)
                target=folder/'upli_receive_tdm_monitor.v';target.write_text(code.replace(old,new,1))
            ref=generate(folder/'vectors.txt',ports)
            case={'ports':ports,'fault':fault,'reference':ref,'commands':{}}
            cmds=case['commands']
            files=([target] if target.exists() else [])+[source/'receive_tdm_tb.sv']
            cmds['compile']=run(folder,'compile',['iverilog','-g2012','-s','receive_tdm_tb',f'-Preceive_tdm_tb.PORTS={ports}','-o','sim.vvp',*files])
            if cmds['compile']['returncode']==0:
                cmds['simulate']=run(folder,'simulate',['vvp','sim.vvp','+VECTORS=vectors.txt',f'+ROWS={ref["rows"]}'])
                if not fault:
                    top='upli_receive_tdm_monitor'
                    for name,command in {
                        'g2001':['iverilog','-g2001','-s',top,f'-P{top}.C_NUM_PORTS={ports}','-o','elab.vvp',target],
                        'lint':['verilator','--lint-only','--language','1364-2001','-Wall','--top-module',top,f'-GC_NUM_PORTS={ports}',target],
                        'yosys':['yosys','-Q','-T','-p',f'read_verilog {target}; chparam -set C_NUM_PORTS {ports} {top}; hierarchy -check -top {top}; proc; opt; check -assert; stat; write_json netlist.json']}.items():
                        cmds[name]=run(folder,name,command)
            log=(folder/'simulate.log').read_text() if (folder/'simulate.log').exists() else ''
            case['passed']=all(c['returncode']==0 for c in cmds.values()) and 'TDM_PASS' in log
            if fault:case['passed']=cmds['compile']['returncode']==0 and cmds.get('simulate',{}).get('returncode')==1 and ('TDM_PRE' in log or 'TDM_POST' in log)
            cases.append(case)
            print(ports,fault,case['passed'],flush=True)
    if args.station:
        station_root=args.station_root.resolve()
        manifest=station_root/'third_party/kd28_dependency.json'
        manifest_blob=manifest.read_bytes();(source/'kd28_dependency.json').write_bytes(manifest_blob)
        hashes[str(manifest)]=hashlib.sha256(manifest_blob).hexdigest()
        deps=json.loads(manifest_blob)['functional_sources_sha256']
        station_sources=[]
        selected=[f for f in (station_root/'rtl').rglob('*.v') if f.name!='upli_receive_tdm_monitor.v']
        for name,expected in deps.items():
            f=args.kd28_root.resolve()/name
            if hashlib.sha256(f.read_bytes()).hexdigest()!=expected:raise ValueError('KD28 dependency hash mismatch '+name)
            selected.append(f)
        selected.append(station_root/'verification/upli_channels/station_tx_tb.sv')
        station_source=stage/'station_source';station_source.mkdir()
        for f in selected:
            blob=f.read_bytes()
            if f in [args.kd28_root.resolve()/n for n in deps] and hashlib.sha256(blob).hexdigest()!=deps[str(f.relative_to(args.kd28_root.resolve()))]:
                raise ValueError('KD28 dependency changed during snapshot')
            dest=station_source/f.name
            if dest.exists():raise ValueError('source basename collision '+f.name)
            dest.write_bytes(blob);hashes[str(f)]=hashlib.sha256(blob).hexdigest();station_sources.append(dest)
        for ports in ([args.ports] if args.ports else [1,2,4]):
            folder=stage/f'station_p{ports}';folder.mkdir()
            commands={}
            commands['compile']=run(folder,'compile',['iverilog','-g2012','-s','receive_tdm_station_tb',f'-Preceive_tdm_station_tb.PORTS={ports}','-o','sim.vvp',rtl,source/'receive_tdm_station_tb.sv',*station_sources])
            if commands['compile']['returncode']==0:
                commands['simulate']=run(folder,'simulate',['vvp','sim.vvp'])
            log=(folder/'simulate.log').read_text() if (folder/'simulate.log').exists() else ''
            passed=all(c['returncode']==0 for c in commands.values()) and 'TDM_STATION_PASS' in log and len(re.findall(r'^STATION_PASS ports=',log,re.M))==2 and len(re.findall(r'^TDM_STATION_PASS ports=',log,re.M))==1 and 'TDM_STATION_COVERAGE' not in log
            cases.append({'ports':ports,'station':True,'commands':commands,'passed':passed})
            print('station',ports,passed,flush=True)
    result={'passed':all(c['passed'] for c in cases),'cases':cases,'sources_sha256':hashes,
            'artifacts_sha256':{str(f.relative_to(stage)):hashlib.sha256(f.read_bytes()).hexdigest() for f in stage.rglob('*') if f.is_file()}}
    (stage/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())

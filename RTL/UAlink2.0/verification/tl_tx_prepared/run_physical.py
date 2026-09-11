"""Run: python3 verification/tl_tx_prepared/run_physical.py --lib-root PATH
--kd28-root PATH --sta PATH --label physical [--widths 8 16].
Map actual production RTL; measure 5 corners x 3 synthetic SRAM views x 2 periods.
Outputs snapshots, mapped netlists, inventories, full STA logs and results.json.
Exit 1 preserves timing violations. Next mapped equivalence, timing repair and
characterized macro qualification; full protocol/IP signoff remains separate.
"""
from pathlib import Path
import argparse
import json
import os
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha
from timing_report import measure

CORNERS=('tt0p9v25c','ssg0p81v125c','ssg0p81vm40c','ffg0p99v125c','ffg0p99vm40c')
VIEWS=('fast','typical','slow')
NAMES=('tl_tx_prepared','tl_prepared_partition','tl_tx_buffered','tl_tx_data_fifo','tl_tx_channels','tl_tx_packer','tl_tx_packer_core','tl_credit_admission','tl_control_decode','tl_control_tenure')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('lib-root','kd28-root','sta'):p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--label',required=True);p.add_argument('--widths',type=int,nargs='+',choices=(8,16),default=[8,16]);a=p.parse_args()
    need(a.label.replace('_','').replace('-','').isalnum() and len(a.widths)==len(set(a.widths)),'invalid label/widths')
    base=ROOT/'build/verification/tl_tx_prepared'/a.label;base.mkdir(exist_ok=False)
    src=[ROOT/'rtl/tl'/(n+'.v') for n in NAMES]+[ROOT/'rtl/upli'/(n+'.v') for n in ('upli_receive_fifo','upli_receive_storage')]
    scripts=[ROOT/'scripts'/n for n in ('map_tl_tx_prepared.tcl','sta_tl_tx_prepared.tcl','credit_abc.constr')]
    external=a.kd28_root.resolve();deps=[external/'Library/models/kd28'/n for n in ('sram/rtl/kd28_sram_blackboxes.v','fifo/rtl/kd28_fifo_sdp_storage_map.v')]
    libs={c:a.lib_root.resolve()/('tcbn28hpcplusbwp40p140'+c+'.lib') for c in CORNERS}
    macros={v:external/'Library/timing/kd28/sram'/('kd28_sram_'+v+'.lib') for v in VIEWS}
    need(all(x.is_file() for x in src+scripts+deps+list(libs.values())+list(macros.values())+[a.sta]),'missing input')
    snapshot=base/'sources';snapshot.mkdir()
    for x in src:(snapshot/x.name).write_bytes(x.read_bytes())
    for x in scripts:(base/x.name).write_bytes(x.read_bytes())
    (base/'runner.py').write_bytes(Path(__file__).read_bytes());(base/'timing_report.py').write_bytes(Path(__file__).with_name('timing_report.py').read_bytes())
    report=dict(complete=False,sources={str(x):sha(x) for x in src+scripts+deps},
                libraries={c:dict(path=str(x),sha256=sha(x)) for c,x in libs.items()},
                synthetic_macros={v:dict(path=str(x),sha256=sha(x)) for v,x in macros.items()},
                sta=dict(path=str(a.sta.resolve()),sha256=sha(a.sta)),results=[],mapped_equivalence=False,macro_signoff=False,full_goal_complete=False)
    dump(base/'results.json',report)
    for width in a.widths:
        folder=base/f'w{width}';folder.mkdir()
        env=dict(UALINK_LIBERTY=str(libs['ssg0p81v125c']),UALINK_KD28_ROOT=str(external),UALINK_BUILD_DIR=str(folder),UALINK_WIDTH=str(width),UALINK_SOURCE_DIR=str(snapshot))
        # Environment arguments avoid Tcl/shell interpolation of caller paths.
        command=['env',*[k+'='+v for k,v in env.items()],'yosys','-Q','-T','-c',str(scripts[0])]
        dump(folder/'map_command.json',command)
        row=dict(width=width,mapping=execute(command,folder/'map.log',600),sta=[]);report['results'].append(row);dump(base/'results.json',report)
        if row['mapping']['exit']!=0:continue
        graph=json.loads((folder/'mapped.json').read_text());top=graph['modules']['tl_tx_prepared'];cells=top['cells'];clock=top['ports']['i_clk']['bits']
        memories=[c for c in cells.values() if c['type'].startswith('KD28_SRAM')]
        flops=[c for c in cells.values() if c['type'].startswith('DF')]
        need(len(memories)==64 and all(c['type']=='KD28_SRAM_SDP_256X32' and c['connections']['RCLK']==clock and c['connections']['WCLK']==clock for c in memories),'mapped SRAM inventory/clock changed')
        need(flops and all(c['connections'].get('CP')==clock for c in flops),'mapped FF clock changed')
        need(not any(c['type'].startswith('$') for c in cells.values()),'unmapped generic cells')
        area=json.loads((folder/'area.json').read_text())
        row.update(netlist_sha256=sha(folder/'mapped.v'),graph_sha256=sha(folder/'mapped.json'),cells=len(cells),ff_cells=len(flops),macro_cells=64,standard_cell_area_um2=area['design']['area'])
        print('mapped',width,row['cells'],row['standard_cell_area_um2'],flush=True)
        for corner,liberty in libs.items():
            for view,macro in macros.items():
                for period in ('0.640','6.400'):
                    name=f'{corner}_{view}_{period}';log=folder/(name+'.log')
                    env=dict(UALINK_LIBERTY=str(liberty),UALINK_MACRO_LIBERTY=str(macro),UALINK_NETLIST=str(folder/'mapped.v'),UALINK_WIDTH=str(width),UALINK_MACRO_VIEW=view,UALINK_PERIOD_NS=period)
                    command=['env',*[k+'='+v for k,v in env.items()],str(a.sta.resolve()),'-exit',str(scripts[1])]
                    dump(folder/(name+'_command.json'),command)
                    run=execute(command,log,120);entry=dict(corner=corner,view=view,period=period,run=run,log_sha256=sha(log),measurement_complete=False)
                    try:entry.update(measure(log.read_text(),width=width,view=view,period=period,exit_code=run['exit']))
                    except ValueError as error:entry['diagnostic']=str(error)
                    row['sta'].append(entry);dump(base/'results.json',report)
        print('measured',width,sum(x['measurement_complete'] for x in row['sta']),sum(x.get('timing_closed',False) for x in row['sta']),flush=True)
    report['complete']=len(report['results'])==len(a.widths) and all(r['mapping']['exit']==0 and len(r['sta'])==30 and all(x['measurement_complete'] for x in r['sta']) for r in report['results'])
    report['all_timing_closed']=report['complete'] and all(x['timing_closed'] for r in report['results'] for x in r['sta'])
    need(all(sha(Path(n))==v for n,v in report['sources'].items()),'source changed during run')
    need(all(sha(Path(v['path']))==v['sha256'] for group in (report['libraries'],report['synthetic_macros']) for v in group.values()),'library changed during run')
    dump(base/'results.json',report);return 0 if report['all_timing_closed'] else 1


if __name__=='__main__':raise SystemExit(main())

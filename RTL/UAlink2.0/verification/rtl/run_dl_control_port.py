"""Freeze and execute actual Control/Basic/UART with authorized KD28 SRAM models.
Run: python3 verification/rtl/run_dl_control_port.py --kd28-root /authorized/root --period-ps 640 --seed 17
Outputs a build snapshot, vectors, compile/simulation logs and exact summary.json.
Next: inspect failures and expand integration coverage; STA requires separate evidence.
"""
import argparse,hashlib,json,re,shutil,subprocess,sys,tempfile,time
from pathlib import Path
DEPENDENCIES=('Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v','Library/models/kd28/sram/rtl/kd28_sram_sp_model.v','Library/models/kd28/sram/rtl/kd28_sram_sdp_model.v','Library/models/kd28/sram/rtl/kd28_sram_tdp_model.v','Library/models/kd28/sram/rtl/kd28_sram_cells.v')
RTL=('rtl/upli/upli_receive_fifo.v','rtl/upli/upli_receive_storage.v','rtl/dl/dl_uart_tx_source.v','rtl/dl/dl_message_arbiter.v','rtl/dl/dl_uart_tx_path.v','rtl/dl/dl_uart_rx_path.v','rtl/dl/dl_uart_reset_control.v','rtl/dl/dl_uart_port.v','rtl/dl/dl_basic_message_control.v','rtl/dl/dl_message_port.v','rtl/dl/dl_control_controller.v','rtl/dl/dl_control_port.v')
STATS='rows records writes discards payloads reads rx_writes rx_discards tx_flush rx_flush noops requests replies starts retries dones normal_messages credits resets stream_edges blocked_start_edges drain_closed_payloads ctl_tx ctl_local_done ctl_remote_done ctl_width_events ctl_auto ctl_deadline_errors'.split()

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True)
    p.add_argument('--tx-depth',type=int,default=128);p.add_argument('--rx-depth',type=int,default=128);p.add_argument('--period-ps',type=int,choices=(640,6400),default=640);p.add_argument('--seed',type=int,default=17);p.add_argument('--no-model',action='store_true');p.add_argument('--verilator',default='verilator')
    p.add_argument('--role',choices=('accelerator','switch'),default='accelerator');p.add_argument('--lanes',type=int,default=4)
    for n,d in [('folding',1),('resiliency',1),('initial-width',0),('allowed-pl-mask',3),('tx-ready-support',0)]:p.add_argument('--'+n,type=int,default=d)
    a=p.parse_args();root=Path(__file__).resolve().parents[2];ext=a.kd28_root.resolve(strict=True)
    if not(1<=a.tx_depth<=4095 and 1<=a.rx_depth<=4095):p.error('invalid capacity')
    files=RTL+tuple('verification/rtl/'+n for n in ('dl_control_port_tb.v','dl_control_port_vectors.py','dl_control_controller_vectors.py','run_dl_control_port.py'))+tuple('config/'+n for n in ('dl_control_port_contract.json','dl_control_controller_contract.json','dl_message_port_contract.json','kd28_verilator.vlt'))+tuple(str(p.relative_to(root)) for p in sorted((root/'model').rglob('*.py')))
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();missing=[n for n in files if not(root/n).is_file()];hashes={n:sha(root/n) for n in files if (root/n).is_file()};deps={n:sha(ext/n) for n in DEPENDENCIES}
    (root/'build').mkdir(exist_ok=True);run=Path(tempfile.mkdtemp(prefix='dl_control_port_run_',dir=root/'build'));snap=run/'snapshot'
    for n in hashes:(snap/n).parent.mkdir(exist_ok=True,parents=True);shutil.copy2(root/n,snap/n)
    params=dict(C_TX_DEPTH=a.tx_depth,C_RX_DEPTH=a.rx_depth,C_ROLE_SWITCH=int(a.role=='switch'),C_LANES=a.lanes,C_FOLDING=a.folding,C_RESILIENCY=a.resiliency,C_INITIAL_WIDTH=a.initial_width,C_ALLOWED_PL_MASK=a.allowed_pl_mask,C_TX_READY_SUPPORT=a.tx_ready_support)
    flags=['--role',a.role,'--lanes',a.lanes,'--folding',a.folding,'--resiliency',a.resiliency,'--initial-width',a.initial_width,'--allowed-pl-mask',a.allowed_pl_mask,'--tx-ready-support',a.tx_ready_support]
    record=dict(directory=str(run.relative_to(root)),source_sha256=hashes,missing_sources=missing,dependency_root=str(ext),dependency_sha256=deps,parameters=params,seed=a.seed,period_ps=a.period_ps,no_model=a.no_model,full_actual_clock=True,stages=[],passed=False,verilator=subprocess.check_output([a.verilator,'--version'],text=True,timeout=20).strip());start=time.monotonic()
    def check():
        if not all(sha(root/n)==sha(snap/n)==h for n,h in hashes.items()):raise RuntimeError('source changed')
        if not all(sha(ext/n)==h for n,h in deps.items()):raise RuntimeError('dependency changed')
    def invoke(cmd,name,timeout):
        check();cmd=list(map(str,cmd))
        with (run/name).open('w') as log:
            try:status=subprocess.run(cmd,cwd=snap,stdout=log,stderr=subprocess.STDOUT,timeout=timeout).returncode
            except subprocess.TimeoutExpired:status=124
        record['stages'].append(dict(command=cmd,log=name,exit_status=status,sha256=sha(run/name)));check()
        if status:raise RuntimeError(f'{name} failed with exit {status}')
    try:
        invoke([sys.executable,'verification/rtl/dl_control_port_vectors.py','--tx-depth',a.tx_depth,'--rx-depth',a.rx_depth,'--period-ps',a.period_ps,'--seed',a.seed,*flags,'--output',run/'vectors.mem','--summary',run/'vectors.json'],'vectors.log',600)
        expected=json.loads((run/'vectors.json').read_text());record.update(expected=expected,vectors_sha256=sha(run/'vectors.mem'),vectors_summary_sha256=sha(run/'vectors.json'))
        invoke([a.verilator,'--binary','--timing','--language','1364-2001','-Wall','--top-module','dl_control_port_tb','--Mdir',run/'obj',f'-GC_HALF_PERIOD_PS={a.period_ps//2}',*(f'-G{k}={v}' for k,v in params.items()),'config/kd28_verilator.vlt',*RTL,'verification/rtl/dl_control_port_tb.v',*(ext/n for n in DEPENDENCIES)],'compile.log',300)
        invoke([run/'obj/Vdl_control_port_tb',f'+VECTORS={run}/vectors.mem']+(['+NO_MODEL'] if a.no_model else []),'sim.log',600)
        matches=re.findall(r'^PASS dl_control_port '+' '.join(k+r'=(\d+)' for k in STATS)+r'$',(run/'sim.log').read_text(),re.M)
        if len(matches)!=1:raise RuntimeError('missing or duplicate PASS')
        observed=dict(zip(STATS,map(int,matches[0])))
        if not all(v==expected[k] for k,v in observed.items()):raise RuntimeError(f'statistics differ: {observed}')
        if not all(observed[n] for n in ['ctl_tx','ctl_local_done','ctl_remote_done','payloads','reads','drain_closed_payloads']):raise RuntimeError('integration coverage missing')
        record.update(observed=observed,passed=True,source_unchanged=True,dependencies_unchanged=True)
    except (RuntimeError,AssertionError,OSError) as e:record['failure']=str(e)
    record['elapsed_seconds']=time.monotonic()-start;(run/'summary.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record),flush=True)
    return 0 if record['passed'] else 1

if __name__=='__main__':raise SystemExit(main())

"""Run two actual Control/Basic/UART RTL ports with four authorized SRAMs.
Run: python3 verification/rtl/run_dl_control_port_peer.py --kd28-root /authorized/root
Outputs: build/control_port_peer_*/{snapshot,compile.log,sim.log,summary.json}.
Next: audit parameter/fault coverage, then independent proof and process STA.
The ordered message queue and external credit scheduler are test abstractions.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
from run_dl_control_port import RTL, DEPENDENCIES


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kd28-root', type=Path, required=True)
    parser.add_argument('--period-ps', type=int, choices=(640, 6400), default=640)
    parser.add_argument('--depth', type=int, default=128)
    parser.add_argument('--seed', type=int, default=17)
    parser.add_argument('--peer-switch', type=int, choices=(0, 1), default=1)
    parser.add_argument('--drop-response',type=int,choices=(0,1),default=0)
    parser.add_argument('--fault', choices=('none', 'control_rx_lost', 'uart_data', 'control_reset', 'pending_target', 'retry_early'), default='none')
    args = parser.parse_args()
    if not 1 <= args.depth <= 4095:
        parser.error('depth must be 1..4095')
    root = Path(__file__).resolve().parents[2]
    ext = args.kd28_root.resolve(strict=True)
    names = list(RTL) + ['verification/rtl/run_dl_control_port.py', 'verification/rtl/run_dl_control_port_peer.py',
                           'verification/rtl/dl_control_port_peer_body.svh', 'config/dl_control_port_contract.json', 'config/kd28_verilator.vlt']
    (root/'build').mkdir(exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='control_port_peer_', dir=root/'build'))
    snap = run/'snapshot'
    hashes = {name: sha(root/name) for name in names}
    deps = {name: sha(ext/name) for name in DEPENDENCIES}
    for name in names:
        (snap/name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root/name, snap/name)
    ports = json.loads((snap/'config/dl_control_port_contract.json').read_text())['interfaces']['ports']
    text = ['`timescale 1ps/1ps', 'module dl_control_port_peer_tb;',
            f'localparam integer C_HALF_PERIOD_PS={args.period_ps//2};', f'localparam integer C_PEER_SWITCH={args.peer_switch};', f'localparam integer C_DROP_RESPONSE={args.drop_response};', 'logic clk=0;']
    for port in ports:
        if port['name']=='i_clk':
            continue
        width = port['width']
        text.append(f"{'logic' if port['direction']=='input' else 'wire'} [{width-1}:0] {port['name']}[2];")
    text += ['wire observation[2];', 'for(genvar e=0;e<2;e=e+1) begin: endpoints',
             f'dl_control_port #(.C_CLOCK_PERIOD_PS({args.period_ps}),.C_TX_DEPTH({args.depth}),.C_RX_DEPTH({args.depth}),.C_ROLE_SWITCH(e==1 ? {args.peer_switch} : 0)) dut (']
    text.append(',\n'.join(f".{p['name']}({'clk' if p['name']=='i_clk' else p['name']+'[e]'})" for p in ports))
    text += [');', 'assign observation[e]=^{'+','.join(p['name']+'[e]' for p in ports if p['direction']=='output')+'};', 'end']
    body = (snap/'verification/rtl/dl_control_port_peer_body.svh').read_text()
    defaults = '\n'.join(f"        {p['name']}[e]='0;" for p in ports if p['direction']=='input' and p['name']!='i_clk')
    text += [body.replace('// INPUT_DEFAULTS', defaults), 'endmodule']
    tb = snap/'verification/rtl/dl_control_port_peer_tb.sv'
    tb.write_text('\n'.join(text)+'\n')
    mutation = None
    if args.fault != 'none':
        if args.fault=='pending_target':
            path=snap/'rtl/dl/dl_control_controller.v'
            old,new='n_owed_channel = n_remote_word;', "n_owed_channel = n_remote_word ^ 32'h00040000;"
        elif args.fault=='retry_early':
            path=snap/'rtl/dl/dl_uart_reset_control.v'
            old,new='cnt_wait == C_WAIT_LAST', "cnt_wait == C_WAIT_LAST-1'b1"
        else:
            path=snap/'rtl/dl/dl_control_port.v'
            old,new = {
                'control_rx_lost': ('.i_rx_valid(o_msg_unhandled_valid)', ".i_rx_valid(1'b0 & o_msg_unhandled_valid)"),
                'uart_data': ('.i_fw_tx_word(i_fw_tx_word)', ".i_fw_tx_word(i_fw_tx_word ^ 32'h00000001)"),
                'control_reset': ('.i_rstn(i_rstn)', '.i_rstn(i_rstn && !o_msg_uart_stream_reset)')
            }[args.fault]
        source=path.read_text()
        prefix=''
        if args.fault=='control_reset':
            index=source.index('dl_control_controller #(')
            prefix,source=source[:index],source[index:]
        if source.count(old)!=1:
            raise RuntimeError('mutation anchor not unique')
        path.write_text(prefix+source.replace(old,new))
        mutation = dict(file=str(path.relative_to(snap)), old=old, new=new, sha256=sha(path))
    frozen = {str(p.relative_to(snap)):sha(p) for p in snap.rglob('*') if p.is_file()}
    record = dict(directory=str(run.relative_to(root)),parameters=dict(period_ps=args.period_ps,depth=args.depth,peer_switch=args.peer_switch,drop_response=args.drop_response),seed=args.seed,
                  fault=args.fault,mutation=mutation,source_sha256=hashes,snapshot_sha256=frozen,dependency_root=str(ext),dependency_sha256=deps,
                  verilator=subprocess.check_output(['verilator','--version'],text=True).strip(),stages=[],passed=False)
    started=time.monotonic()
    try:
        commands = [('compile.log',['verilator','--binary','--timing','--language','1800-2017','-Wall','--top-module','dl_control_port_peer_tb','--Mdir',str(run/'obj'),'config/kd28_verilator.vlt',*RTL,str(tb),*(str(ext/n) for n in DEPENDENCIES)]),
                    ('sim.log',[str(run/'obj/Vdl_control_port_peer_tb'),f'+SEED={args.seed}'])]
        for log,command in commands:
            with (run/log).open('w') as output:
                result=subprocess.run(command,cwd=snap,stdout=output,stderr=subprocess.STDOUT,timeout=300)
            record['stages'].append(dict(command=command,log=log,exit_status=result.returncode,sha256=sha(run/log)))
            if result.returncode:
                raise RuntimeError(f'{log} failed: {result.returncode}')
        matches=re.findall(r'^PASS dl_control_port_peer cycles=(\d+) received0=(\d+) received1=(\d+) width0=(\d+) width1=(\d+) checksum=[01] ignored=1$',(run/'sim.log').read_text(),re.M)
        if len(matches)!=1 or tuple(map(int,matches[0][1:]))!=(128,128,2-args.peer_switch,2-args.peer_switch):
            raise RuntimeError('missing unique PASS or insufficient behavior coverage')
        life=re.findall(r'^LIFECYCLE pending=(\d+) restarts=(\d+) reset_done0=(\d+) reset_done1=(\d+) requests0=(\d+) requests1=(\d+) retries=(\d+) drops=(\d+)$',(run/'sim.log').read_text(),re.M)
        expected=(2-args.peer_switch,2-args.peer_switch,2,2-args.peer_switch,2+args.drop_response,2-args.peer_switch,args.drop_response,args.drop_response)
        if len(life)!=1 or tuple(map(int,life[0]))!=expected: raise RuntimeError('lifecycle coverage missing')
        record['lifecycle']=dict(zip(['pending','restarts','reset_done0','reset_done1','requests0','requests1','retries','drops'],map(int,life[0])))
        record.update(passed=True,observed=dict(zip(['cycles','received0','received1','width0','width1'],map(int,matches[0]))))
    except (RuntimeError,subprocess.TimeoutExpired) as error:
        record['failure']=str(error)
    unchanged = all(sha(root/n)==h for n,h in hashes.items()) and all(sha(ext/n)==h for n,h in deps.items()) and all(sha(snap/n)==h for n,h in frozen.items())
    record.update(source_unchanged=unchanged,elapsed_seconds=time.monotonic()-started)
    record['passed'] = record['passed'] and unchanged
    (run/'summary.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record),flush=True)
    return 0 if record['passed'] else 1


if __name__=='__main__':
    raise SystemExit(main())

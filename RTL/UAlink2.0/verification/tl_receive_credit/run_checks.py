"""Run: python3 verification/tl_receive_credit/run_checks.py --kd28-root PATH.
Requires run_rtl.py --label matrix; writes lint, synthesis and same-TB fault runs.
Next independent cycle audit and online capacity/formal/STA work.
"""
from pathlib import Path
import argparse,json,subprocess,hashlib
R=Path(__file__).resolve().parents[2];S=R/'build/verification/tl_receive_credit';p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label',default='checks_final');a=p.parse_args();B=S/a.label;B.mkdir(exist_ok=False)
src=sorted((R/'rtl/tl').glob('*.v'))+[R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v'];root=a.kd28_root/'Library/models/kd28'
ext=[root/'sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[root/'fifo/rtl/kd28_fifo_sdp_storage_map.v'];rows=[]
def run(cmd,log,timeout=180):
    try:x=subprocess.run(cmd,capture_output=True,text=True,timeout=timeout);code,text=x.returncode,x.stdout+x.stderr
    except subprocess.TimeoutExpired as e:code,text=124,(e.stdout or b'').decode()+(e.stderr or b'').decode()
    log.write_text(text);return code,text
for width in (8,16):
    code,log=run(['verilator','--lint-only','-Wall','--timescale-override','1ps/1ps','--top-module','tl_receive_credit',f'-GWIDTH={width}','-GDEPTH=100',str(R/'config/kd28_verilator.vlt'),*[str(x) for x in src+ext]],B/f'lint_{width}.log');rows.append(dict(kind='lint',width=width,passed=code==0 and '%Warning' not in log,exit_status=code));print(rows[-1],flush=True)
    ys=B/f'synth_{width}.ys';ys.write_text('read_verilog '+' '.join(str(x) for x in src+[root/'sram/rtl/kd28_sram_blackboxes.v',root/'fifo/rtl/kd28_fifo_sdp_storage_map.v'])+f'\nchparam -set WIDTH {width} -set DEPTH 100 tl_receive_credit\nsynth -top tl_receive_credit -flatten -noabc\ncheck -assert\nwrite_json {B}/synth_{width}.json\nstat\n')
    code,log=run(['yosys','-Q','-T','-s',str(ys)],B/f'synth_{width}.log');row=dict(kind='synth',width=width,exit_status=code,passed=False)
    if code==0:
        m=json.loads((B/f'synth_{width}.json').read_text())['modules']['tl_receive_credit'];clk=m['ports']['i_clk']['bits'];ff=[c for c in m['cells'].values() if 'DFF' in c['type'] or 'LATCH' in c['type']];mac=[c for c in m['cells'].values() if c['type'].startswith('KD28_SRAM')];ok=bool(ff) and len(mac)==19 and all('LATCH' not in c['type'] and c['connections'].get('C')==clk for c in ff) and all(c['connections']['RCLK']==clk and c['connections']['WCLK']==clk for c in mac);row.update(passed=ok,cells=len(m['cells']),ff=sum(len(c['connections']['Q']) for c in ff),sram_cells=len(mac),single_clock=ok)
    rows.append(row);print(row,flush=True)
base=(R/'rtl/tl/tl_receive_credit.v').read_text();changes={
 'early_release':('.i_release_valid(storage_valid&&i_read_ready)', '.i_release_valid(storage_valid)'),
 'lost_release':('.i_release_valid(storage_valid&&i_read_ready)', ".i_release_valid(1'b0)"),
 'wrong_release_slot':('.i_releases(o_read_releases)',".i_releases(o_read_releases ^ 80'd1)"),
 'wrong_complete_shared':("{247'd0,pub_shared,8'd1,256'd0}","{247'd0,!pub_shared,8'd1,256'd0}"),
 'stored_data_bit':('.i_flit(i_flit)',".i_flit(i_flit ^ (512'd1<<300))"),
 'budget_bypass':("({{(26-WIDTH){1'b0}},o_required_words}<=DEPTH)","1'b1"),
 'early_fc_commit':('.i_send(i_fc_send&&!o_fatal)', '.i_send(!o_fatal)')}
for name,(old,new) in changes.items():
    if base.count(old)!=1:raise RuntimeError('mutation anchor '+name)
    d=B/name;d.mkdir();f=d/'tl_receive_credit.v';f.write_text(base.replace(old,new));results=[]
    for tb in sorted((S/'matrix').glob('*/tb.v')):
        out=d/tb.parent.name;out.mkdir();sources=[f if x.name==f.name else x for x in src];local_tb=out/'tb.v';local_tb.write_text(tb.read_text().replace(str(tb.parent/'trace.txt'),str(out/'trace.txt')));cmd=['iverilog','-g2012','-s','tb','-o',str(out/'sim.vvp'),*[str(x) for x in sources+ext],str(local_tb)];code,_=run(cmd,out/'compile.log');row=dict(config=out.name,compile_exit=code,detected=False)
        if code==0:
            code,log=run(['vvp',str(out/'sim.vvp')],out/'run.log',120);row.update(run_exit=code,detected=code==1 and 'FATAL:' in log and 'PASS actual dual SRAM FC' not in log)
        results.append(row)
    row=dict(kind='fault',name=name,results=results,passed=len(results)==16 and all(x['detected'] for x in results),source_sha256=hashlib.sha256(f.read_bytes()).hexdigest());rows.append(row);print(name,row['passed'],flush=True)
(B/'results.json').write_text(json.dumps(dict(complete=all(x['passed'] for x in rows),results=rows),indent=2)+'\n');raise SystemExit(0 if all(x['passed'] for x in rows) else 1)

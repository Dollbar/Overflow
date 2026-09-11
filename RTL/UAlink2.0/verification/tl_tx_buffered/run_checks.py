"""Run python3 verification/tl_tx_buffered/run_checks.py --kd28-root PATH.
Requires healthy none/deeper peers and fifo runs. Outputs actual tool/mutation logs;
next check_evidence.py, clean-export compatibility and local commit.
"""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys
R=Path(__file__).resolve().parents[2];p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label',default='checks_cover');p.add_argument('--reuse-checks',type=Path);p.add_argument('--resume-fifo',action='store_true');a=p.parse_args();S=R/'build/verification/tl_tx_buffered';B=S/a.label;B.mkdir(exist_ok=a.resume_fifo)
src=[R/'rtl/tl'/n for n in ('tl_tx_buffered.v','tl_tx_data_fifo.v','tl_tx_channels.v','tl_tx_packer.v','tl_tx_packer_core.v','tl_credit_admission.v','tl_control_decode.v','tl_control_tenure.v')]+[R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v'];root=a.kd28_root/'Library/models/kd28';ext=[root/'sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[root/'fifo/rtl/kd28_fifo_sdp_storage_map.v'];rows=[]
def run(name,cmd):
    c=subprocess.run(cmd,capture_output=True,text=True,timeout=240);(B/(name+'.log')).write_text(c.stdout+c.stderr);return c
if a.reuse_checks:
    reused_result=json.loads((a.reuse_checks/'results.json').read_text())
    if any(hashlib.sha256(Path(name).read_bytes()).hexdigest()!=sha for name,sha in reused_result['sources'].items()):raise ValueError('reused tool results source mismatch')
    rows.extend(x for x in reused_result['results'] if x['kind'] in ('lint','synthesis'))
    import shutil
    for w in (8,16):
        for name in (f'lint_{w}.log',f'synth_{w}.log',f'synth_{w}.json',f'synth_{w}.ys'):shutil.copy2(a.reuse_checks/name,B/name)
else:
    for w in (8,16):
        c=run(f'lint_{w}',['verilator','--lint-only','-Wall','--timescale-override','1ps/1ps','--top-module','tl_tx_buffered',f'-GWIDTH={w}',str(R/'config/kd28_verilator.vlt'),*map(str,src+ext)]);rows.append(dict(kind='lint',width=w,passed=c.returncode==0));print(rows[-1],flush=True)
        script='read_verilog '+' '.join(map(str,src+[root/'sram/rtl/kd28_sram_blackboxes.v',ext[-1]]))+f'\nchparam -set WIDTH {w} tl_tx_buffered\nsynth -flatten -noabc -top tl_tx_buffered\ncheck -assert\nwrite_json {B}/synth_{w}.json\nstat\n';(B/f'synth_{w}.ys').write_text(script);c=run(f'synth_{w}',['yosys','-Q','-T','-s',str(B/f'synth_{w}.ys')]);row=dict(kind='synthesis',width=w,passed=False)
        if c.returncode==0:
            m=json.loads((B/f'synth_{w}.json').read_text())['modules']['tl_tx_buffered'];clk=m['ports']['i_clk']['bits'];ff=[x for x in m['cells'].values() if 'DFF' in x['type'] or 'LATCH' in x['type']];mac=[x for x in m['cells'].values() if x['type'].startswith('KD28_SRAM')];ok=len(mac)==64 and all('LATCH' not in x['type'] and x['connections'].get('C')==clk for x in ff) and all(x['connections']['RCLK']==clk and x['connections']['WCLK']==clk for x in mac);row.update(passed=ok,cells=len(m['cells']),ff_bits=sum(len(x['connections']['Q']) for x in ff),sram_cells=len(mac),single_clock=ok)
        rows.append(row);print(row,flush=True)
fifo=(R/'rtl/tl/tl_tx_data_fifo.v').read_text();mutations={
 'lost_write_phase':('r_write_bank<=!r_write_bank','r_write_bank<=r_write_bank'),
 'lost_read_phase':('r_read_bank<=!r_read_bank','r_read_bank<=r_read_bank'),
 'swapped_bank_data':('r_write_bank?i_data1:i_data0','r_write_bank?i_data0:i_data1'),
 'lost_partial_accept':("o_write_taken=!write_fire?2'd0:","o_write_taken=(!write_fire||((i_write_count==2'd2)&&!write_ready[!r_write_bank]))?2'd0:"),
 'invalid_take_consumes':("read_legal=i_rstn&&(i_take<=o_valid_count)",'read_legal=i_rstn'),
 'count_excludes_bank':("{1'b0,count0}+{1'b0,count1}","{1'b0,count0}"),
}
for name,(old,new) in mutations.items():
    if fifo.count(old)!=1:raise ValueError('mutation anchor '+name)
    d=B/name;d.mkdir(exist_ok=a.resume_fifo);f=d/'tl_tx_data_fifo.v'
    if a.resume_fifo:
        if f.read_text()!=fifo.replace(old,new):raise ValueError('resumed mutant source differs')
        result=json.loads((S/('fault_cover_'+name)/'results.json').read_text())
        if any(hashlib.sha256(Path(n).read_bytes()).hexdigest()!=sha for n,sha in result['sources'].items()):raise ValueError('resumed FIFO source identity')
        rows.append(dict(kind='fifo_fault',name=name,passed=len(result['results'])==6 and all(x['compile_exit']==0 and x.get('run_exit')==1 for x in result['results'])));continue
    f.write_text(fifo.replace(old,new));c=run(name,[sys.executable,str(R/'verification/tl_tx_buffered/run_fifo.py'),'--kd28-root',str(a.kd28_root),'--label','fault_cover_'+name,'--replace',str(f)]);result=json.loads((S/('fault_cover_'+name)/'results.json').read_text());rows.append(dict(kind='fifo_fault',name=name,passed=c.returncode==1 and len(result['results'])==6 and all(x['compile_exit']==0 and x.get('run_exit')==1 for x in result['results'])));print(rows[-1],flush=True)
if a.reuse_checks:
    rows.extend(x for x in reused_result['results'] if x['kind']=='peer_fault')
    for row in reused_result['results']:
        if row['kind']=='peer_fault':
            name=row['name']+'_'+row['config']+'.log';shutil.copy2(a.reuse_checks/name,B/name)
else:
    wrapper=(R/'rtl/tl/tl_tx_buffered.v').read_text();peer_faults={
     'early_header_pop':('.i_read_ready(header_taken[lane])','.i_read_ready(header_valid[lane])','none_final'),
     'wrong_data_queue_ack':('.i_take(data_taken[lane*2+:2])','.i_take(data_taken[(1-lane)*2+:2])','none_final'),
     'bypass_stored_tags':('.i_tags(tags)','.i_tags(i_tags)','deeper_final')}
    for name,(old,new,mode) in peer_faults.items():
        if wrapper.count(old)!=1:raise ValueError('mutation anchor '+name)
        d=B/name;d.mkdir();f=d/'tl_tx_buffered.v';f.write_text(wrapper.replace(old,new));sources=[f if x.name==f.name else x for x in sorted((R/'rtl/tl').glob('*.v'))]+[R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v']+ext
        for source_tb in sorted((S/mode).glob('*/tb.sv')):
            if name=='bypass_stored_tags' and '_a0_' in source_tb.parent.name:continue
            out=d/source_tb.parent.name;out.mkdir();tb=out/'tb.sv';v=source_tb.read_text()
            for log in ('trace.txt','queue_trace.txt'):v=v.replace(str(source_tb.parent/log),str(out/log))
            tb.write_text(v);c=run(name+'_'+out.name+'_compile',['iverilog','-g2012','-s','tb','-o',str(out/'sim.vvp'),*map(str,sources),str(tb)])
            if c.returncode:raise ValueError('actual peer mutant compilation failed')
            c=run(name+'_'+out.name,['vvp',str(out/'sim.vvp')]);rows.append(dict(kind='peer_fault',name=name,config=out.name,passed=c.returncode==1 and 'FATAL:' in c.stdout and 'PASS actual channels' not in c.stdout))
result=dict(reused_checks=str(a.reuse_checks) if a.reuse_checks else None,complete=all(x['passed'] for x in rows),results=rows,sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in src+ext+[root/'sram/rtl/kd28_sram_blackboxes.v']});(B/'results.json').write_text(json.dumps(result,indent=2)+'\n');print('checks complete',result['complete']);raise SystemExit(0 if result['complete'] else 1)

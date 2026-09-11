"""Run: python3 verification/tl_tx_channels/run_checks.py --kd28-root PATH.
Actual lint/synthesis and source-identity-bound unit/dual-peer negative runs.
Outputs checks/; next independent final trace audit and full-goal status update.
"""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys
R=Path(__file__).resolve().parents[2];p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label',default='checks');a=p.parse_args();S=R/'build/verification/tl_tx_channels'/a.label;S.mkdir(parents=True,exist_ok=False)
fault_prefix='' if a.label=='checks' else a.label+'_'
src=[R/'rtl/tl'/n for n in ('tl_tx_channels.v','tl_tx_packer.v','tl_tx_packer_core.v','tl_credit_admission.v','tl_control_decode.v','tl_control_tenure.v')];rows=[]
def run(name,cmd):
    c=subprocess.run(cmd,capture_output=True,text=True,timeout=240);(S/(name+'.log')).write_text(c.stdout+c.stderr);return c
for w in (8,16):
    c=run(f'lint_{w}',['verilator','--lint-only','--top-module','tl_tx_channels','-Wall',f'-GWIDTH={w}',*map(str,src)]);rows.append(dict(kind='lint',width=w,passed=c.returncode==0))
    script=f'read_verilog {" ".join(map(str,src))}\nchparam -set WIDTH {w} tl_tx_channels\nhierarchy -check -top tl_tx_channels\nsynth -flatten -noabc -top tl_tx_channels\ncheck -assert\nwrite_json {S}/synth_{w}.json\n';(S/f'synth_{w}.ys').write_text(script);c=run(f'synth_{w}',['yosys','-Q','-T','-s',str(S/f'synth_{w}.ys')]);rows.append(dict(kind='synthesis',width=w,passed=c.returncode==0));print(rows[-2:],flush=True)
source=src[0].read_text();mutations={
 'ignore_ready':('else if(|ready)','else if(1\'b0)'),
 'selected_data_owner':("(i_pending!=7'd0)?r_owner:selected_class",'selected_class'),
 'lost_owner_update':('else if(header_taken)r_owner<=selected_class;',"else if(1'b0)r_owner<=selected_class;"),
 'no_header_hold':('if(r_hold_valid)selected_class=r_hold_class;',"if(1'b0)selected_class=r_hold_class;"),
 'fixed_request_priority':('r_preferred<=!selected_class;',"r_preferred<=1'b0;"),
 'wrong_data_ack':('o_data_taken=data_class?', 'o_data_taken=selected_class?'),
 'wrong_class_allowed':("&&((lane==0)?(responses==4'd0):(requests==3'd0))",''),
 'hide_budget_nop':('else if(|nop_ready)',"else if(1'b0)"),
}
for name,(old,new) in mutations.items():
    if old not in source:raise ValueError('inactive mutation '+name)
    d=S/name;d.mkdir();f=d/'tl_tx_channels.v';f.write_text(source.replace(old,new));c=run(name,[sys.executable,str(R/'verification/tl_tx_channels/run_rtl.py'),'--label',fault_prefix+'fault_'+name,'--replace',str(f)])
    r=json.loads((R/'build/verification/tl_tx_channels'/(fault_prefix+'fault_'+name)/'results.json').read_text());caught=c.returncode==1 and all(x['compile_exit']==0 and x['run_exit']==1 for x in r['results']);rows.append(dict(kind='unit_fault',name=name,passed=caught));print(rows[-1],flush=True)
external=[a.kd28_root/'Library/models/kd28/sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[a.kd28_root/'Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v']
for fault,mode in (('selected_data_owner','none'),('lost_owner_update','none'),('ignore_ready','request'),('ignore_ready','response')):
    f=S/fault/'tl_tx_channels.v';sources=[f if x.name==f.name else x for x in sorted((R/'rtl/tl').glob('*.v'))]+[R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v']+external
    for source_tb in sorted((R/'build/verification/tl_tx_channels'/mode).glob('*/tb.sv')):
        d=S/(fault+'_'+mode+'_'+source_tb.parent.name);d.mkdir();tb=d/'tb.sv';tb.write_text(source_tb.read_text().replace(str(source_tb.parent/'trace.txt'),str(d/'trace.txt')))
        c=run(d.name+'_compile',['iverilog','-g2012','-s','tb','-o',str(d/'sim.vvp'),*map(str,sources),str(tb)])
        if c.returncode:raise ValueError('dual mutant compile failed')
        c=run(d.name,['vvp',str(d/'sim.vvp')]);rows.append(dict(kind='peer_fault',name=fault,mode=mode,config=source_tb.parent.name,passed=c.returncode==1 and 'FATAL:' in c.stdout and 'PASS actual channels' not in c.stdout))
result=dict(complete=all(x['passed'] for x in rows),results=rows,sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in src});(S/'results.json').write_text(json.dumps(result,indent=2)+'\n');print('checks complete',result['complete']);raise SystemExit(0 if result['complete'] else 1)

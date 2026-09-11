"""Run: python3 verification/tl_tx_packer/run_checks.py --kd28-root PATH.
Actual lint/synthesis, 8 unit fault types and 2 dual-peer wiring faults.
Outputs checks/ and fault traces; next audit the final healthy peer trace.
"""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys
R=Path(__file__).resolve().parents[2];p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label',default='checks');a=p.parse_args();S=R/'build/verification/tl_tx_packer'/a.label;S.mkdir(parents=True,exist_ok=False)
fault_prefix='' if a.label=='checks' else a.label+'_'
src=[R/'rtl/tl'/n for n in ('tl_tx_packer.v','tl_tx_packer_core.v','tl_credit_admission.v','tl_control_decode.v','tl_control_tenure.v')];rows=[]
def run(name,cmd):
    c=subprocess.run(cmd,capture_output=True,text=True,timeout=180);(S/(name+'.log')).write_text(c.stdout+c.stderr);return c
for w in (8,16):
    c=run(f'lint_{w}',['verilator','--lint-only','--top-module','tl_tx_packer','-Wall',f'-GWIDTH={w}',*map(str,src)]);rows.append(dict(kind='lint',width=w,passed=c.returncode==0))
    script=f'read_verilog {" ".join(map(str,src))}\nchparam -set WIDTH {w} tl_tx_packer\nhierarchy -check -top tl_tx_packer\nsynth -flatten -noabc -top tl_tx_packer\ncheck -assert\nwrite_json {S}/synth_{w}.json\n';(S/f'synth_{w}.ys').write_text(script);c=run(f'synth_{w}',['yosys','-Q','-T','-s',str(S/f'synth_{w}.ys')]);rows.append(dict(kind='synthesis',width=w,passed=c.returncode==0))
sources_by_name={name:(R/'rtl/tl'/name).read_text() for name in ('tl_tx_packer.v','tl_tx_packer_core.v')};fault_paths={}
mutations={
 'no_tail_fallback':('selection=SEL_TAIL;', 'selection=SEL_NONE;'),
 'tail_in_lower':('o_flit={i_data0,256\'d0}',"o_flit={256'd0,i_data0}"),
 'consume_header_on_tail':('(selection==SEL_HEADER);','((selection==SEL_HEADER)||(selection==SEL_TAIL));'),
 'lost_paired_fc_ack':('(selection==SEL_FC);',"(selection==SEL_FC)&&(i_pending==7'd0);"),
 'no_stall_hold':('if(r_hold!=SEL_NONE)selection=r_hold;',"if(1'b0)selection=r_hold;"),
 'fixed_fc_priority':('(!i_header_ready||r_prefer_fc)',"(!i_header_ready||1'b1)"),
 'auth_header_with_tail':("&&!(i_auth&&(i_pending==7'd1))",''),
 'no_budget_nop':('selection=SEL_NOP;', 'selection=SEL_NONE;'),
}
for name,(old,new) in mutations.items():
    matching=[filename for filename,text in sources_by_name.items() if old in text]
    if len(matching)!=1:raise ValueError('inactive/ambiguous mutation '+name)
    filename=matching[0];source=sources_by_name[filename]
    d=S/name;d.mkdir();f=d/filename;f.write_text(source.replace(old,new));fault_paths[name]=f;c=run(name,[sys.executable,str(R/'verification/tl_tx_packer/run_rtl.py'),'--label',fault_prefix+'fault_'+name,'--replace',str(f)])
    r=json.loads((R/'build/verification/tl_tx_packer'/(fault_prefix+'fault_'+name)/'results.json').read_text());caught=c.returncode==1 and all(x['compile_exit']==0 and x['run_exit']==1 for x in r['results']);rows.append(dict(kind='unit_fault',name=name,passed=caught));print(rows[-1],flush=True)
# Actual peer faults use exactly the healthy testbench and input hex fixtures.
external=[a.kd28_root/'Library/models/kd28/sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[a.kd28_root/'Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v']
for fault in ('tail_in_lower','consume_header_on_tail'):
    f=fault_paths[fault];sources=[f if x.name==f.name else x for x in sorted((R/'rtl/tl').glob('*.v'))]+[R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v']+external
    for source_tb in sorted((R/'build/verification/tl_tx_packer/peers_final').glob('*/tb.sv')):
        d=S/(fault+'_'+source_tb.parent.name);d.mkdir();tb=d/'tb.sv';tb.write_text(source_tb.read_text().replace(str(source_tb.parent/'trace.txt'),str(d/'trace.txt')))
        c=run(d.name+'_compile',['iverilog','-g2012','-s','tb','-o',str(d/'sim.vvp'),*map(str,sources),str(tb)])
        if c.returncode:raise ValueError('dual mutant compile failed')
        c=run(d.name,['vvp',str(d/'sim.vvp')]);rows.append(dict(kind='peer_fault',name=fault,config=source_tb.parent.name,passed=c.returncode==1 and 'FATAL:' in c.stdout and 'PASS actual packer' not in c.stdout))
result=dict(complete=all(x['passed'] for x in rows),results=rows,sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in src});(S/'results.json').write_text(json.dumps(result,indent=2)+'\n');print('checks complete',result['complete']);raise SystemExit(0 if result['complete'] else 1)

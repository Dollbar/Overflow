"""Run: python3 verification/tl_credit_admission/run_checks.py --kd28-root PATH.
Writes lint, synthesis, parameter and actual mutant results to the stage build dir.
Next: audit source identity and the healthy dual-port traces.
"""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys
R=Path(__file__).resolve().parents[2];p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label',default='checks');a=p.parse_args()
pressure_fixtures=sorted((R/'build/verification/tl_receive_credit/pressure_verified').glob('*/tb.v'))
if len(pressure_fixtures)!=16:p.error('requires all 16 healthy pressure_verified fixtures; generate with tl_receive_credit/run_rtl.py --traffic-pressure --admission --label pressure_verified')
S=R/'build/verification/tl_credit_admission'/a.label;S.mkdir(parents=True,exist_ok=False)
rows=[]
def run(name,cmd):
    x=subprocess.run(cmd,capture_output=True,text=True,timeout=240);(S/f'{name}.log').write_text(x.stdout+x.stderr);return x
sources=sorted((R/'rtl/tl').glob('*.v'))
for w in (8,16):
    x=run(f'lint_{w}',['verilator','--lint-only','--top-module','tl_credit_admitted_port','-Wall',f'-GWIDTH={w}',*map(str,sources)])
    rows.append(dict(kind='lint',width=w,exit=x.returncode,passed=x.returncode==0))
    script=f'read_verilog {" ".join(map(str,sources))}\nchparam -set WIDTH {w} tl_credit_admitted_port\nhierarchy -check -top tl_credit_admitted_port\nsynth -flatten -noabc -top tl_credit_admitted_port\ncheck -assert\nwrite_json {S}/synth_{w}.json\n'
    (S/f'synth_{w}.ys').write_text(script);x=run(f'synth_{w}',['yosys','-Q','-T','-s',str(S/f'synth_{w}.ys')]);rows.append(dict(kind='synth',width=w,exit=x.returncode,passed=x.returncode==0))
    print(rows[-2:],flush=True)
for w in (7,17):
    x=run(f'invalid_{w}',['iverilog','-g2001','-s','tl_credit_admission',f'-Ptl_credit_admission.WIDTH={w}','-o',str(S/f'invalid_{w}.vvp'),*map(str,sources)])
    rows.append(dict(kind='invalid_parameter',width=w,exit=x.returncode,passed=x.returncode!=0 and 'invalid_WIDTH' in x.stderr))
guard=(R/'rtl/tl/tl_credit_admission.v').read_text()
data_lane_change=("(w_slots[field*5+:5]==DATA_SLOT))?{3'd0", "(w_slots[field*5+:5]==((DATA_SLOT==5'd19)?5'd18:DATA_SLOT+5'd1)))?{3'd0")
if "slot_match?{3'd0" in guard:
    # Keep the fault on Data contributions only; invert the dedicated VC match.
    wrong_lane="((((account%10)<5)?w_req[field]:(w_rsp[field]&&!w_req[field]))&&((SLOT_LANE==0)?field_pool[field]:(!field_pool[field]&&(field_vc[field*2+:2]==(SLOT_VC^2'd1)))))"
    data_lane_change=("slot_match?{3'd0",wrong_lane+"?{3'd0")
changes={
 'lose_future_data':('{3\'d0,w_counts[field*4+1+:3]}',"6'd0"),
 'wrong_data_lane':data_lane_change,
 'no_shared_merge':('if(i_shared)begin','if(1\'b0)begin'),
 'merge_vc_pools':("o_requirements[60+:6]+o_requirements[90+:6]","o_requirements[60+:6]+o_requirements[96+:6]"),
 'ignore_available':('(i_done&&(&available_fit))',"(i_done&&1'b1)"),
 'allow_before_init':('(i_done&&(&available_fit))','(&available_fit)'),
}
for name,(old,new) in changes.items():
    if old not in guard:raise RuntimeError('mutation not applied '+name)
    d=S/name;d.mkdir();f=d/'tl_credit_admission.v';f.write_text(guard.replace(old,new));x=run(name,[sys.executable,str(R/'verification/tl_credit_admission/run_rtl.py'),'--label',a.label+'_fault_'+name,'--replace',str(f)])
    result=json.loads((R/'build/verification/tl_credit_admission'/(a.label+'_fault_'+name)/'results.json').read_text())
    caught=x.returncode==1 and all(r['compile_exit']==0 and r.get('run_exit')==1 for r in result['results'])
    rows.append(dict(kind='guard_fault',name=name,passed=caught));print(rows[-1],flush=True)
# The same pressure testbench/fixtures run with the actual wrapper send gate removed.
f=S/'tl_credit_admitted_port.v';f.write_text((R/'rtl/tl/tl_credit_admitted_port.v').read_text().replace('.i_send(i_send&&admission_allow)', '.i_send(i_send)'))
external=[a.kd28_root/'Library/models/kd28/sram/rtl'/n for n in ('kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v','kd28_sram_cells.v')]+[a.kd28_root/'Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v']
used=[f if q.name==f.name else q for q in sources]+[R/'rtl/upli/upli_receive_fifo.v',R/'rtl/upli/upli_receive_storage.v']+external
for source in pressure_fixtures:
    d=S/('bypass_'+source.parent.name);d.mkdir();tb=d/'tb.v';tb.write_text(source.read_text().replace(str(source.parent/'trace.txt'),str(d/'trace.txt')).replace(str(source.parent/'admission_trace.txt'),str(d/'admission_trace.txt')))
    c=run(d.name+'_compile',['iverilog','-g2012','-s','tb','-o',str(d/'sim.vvp'),*map(str,used),str(tb)])
    if c.returncode:raise RuntimeError('mutant did not compile')
    x=run(d.name,['vvp',str(d/'sim.vvp')]);rows.append(dict(kind='wrapper_fault',config=source.parent.name,passed=x.returncode==1 and 'unfunded header sent' in x.stdout))
result=dict(sources={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources+external},complete=all(r['passed'] for r in rows),results=rows);(S/'results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));raise SystemExit(0 if result['complete'] else 1)

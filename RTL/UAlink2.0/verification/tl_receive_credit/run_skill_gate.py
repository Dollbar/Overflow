"""Run: python3 verification/tl_receive_credit/run_skill_gate.py --skill-root PATH.
Writes the real wrapper's artifact validation report; next external HDL checks.
"""
from pathlib import Path
import argparse,json,shutil,sys
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--skill-root',required=True,type=Path);a=p.parse_args();sys.path.insert(0,str(a.skill_root))
from integration.verilog_adapter import validate_verilog_artifacts,analyze_existing_verilog
R=Path(__file__).resolve().parents[2];S=R/'build/verification/tl_receive_credit';d=S/'authored';d.mkdir(exist_ok=True);shutil.copy2(R/'rtl/tl/tl_receive_credit.v',d/'tl_receive_credit.v')
spec={'name':'tl_receive_credit','target':'rtl','rtl_dialect':'verilog','rtl_style_profile':'erie_strict','description':'Single-clock native hierarchical SRAM retirement and FC publication wrapper. No new pipeline registers beyond instantiated children.','pipeline_required':True,'codegen_plan_required':True,'streamability':'streamable','interface_family':'native','design_requirements':{'target':'rtl','pipeline_required':True,'streamability':'streamable','interface_family':'native','interface_profile':{},'confirmed_by_user':True},'interfaces':{'ports':[{'name':'i_clk','direction':'input','width':1,'role':'clock'},{'name':'i_rstn','direction':'input','width':1,'role':'reset'}]},'clock':{'name':'i_clk','edge':'posedge','frequency_mhz':1562.5},'reset':{'name':'i_rstn','active':'low','synchronous':True},'outputs':[{'path':'tl_receive_credit.v','kind':'rtl'}]}

for name in ('tl_receive_storage.v','tl_credit_publish.v'):
    (d/name).unlink(missing_ok=True)
(d/'tl_receive_credit.v').write_text('\n'.join((R/'rtl/tl'/name).read_text() for name in ('tl_receive_credit.v','tl_receive_storage.v','tl_credit_publish.v')))
(S/'skill_spec.json').write_text(json.dumps(spec,indent=2)+'\n');r=validate_verilog_artifacts(spec,d,run_external=False,readiness='static',report_json=S/'skill_gate.json');print(json.dumps(r,ensure_ascii=False));analyze_existing_verilog(R/'rtl/tl/tl_receive_credit.v',out_dir=S/'analysis',module_name='tl_receive_credit')

raise SystemExit(0 if r['ok'] else 1)

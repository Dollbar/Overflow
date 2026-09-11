"""Run: python3 verification/tl_tx_buffered/run_skill_gate.py --skill-root PATH.
Writes real authored RTL artifact validation and analysis; next review external checks.
"""
from pathlib import Path
import argparse,json,sys
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--skill-root',type=Path,required=True);a=p.parse_args();sys.path.insert(0,str(a.skill_root))
from integration.verilog_adapter import validate_verilog_artifacts,analyze_existing_verilog
R=Path(__file__).resolve().parents[2];S=R/'build/verification/tl_tx_buffered';D=S/'authored';D.mkdir(exist_ok=True)
(D/'tl_tx_buffered.v').write_text('\n'.join((R/'rtl/tl'/f).read_text() for f in ('tl_tx_buffered.v','tl_tx_data_fifo.v')))
spec={'name':'tl_tx_buffered','target':'rtl','rtl_dialect':'verilog','rtl_style_profile':'erie_strict','description':'Independent Request/Response SRAM transmit queues, partial input acceptance and atomic actual-wire retirement; one input clock.','pipeline_required':True,'codegen_plan_required':True,'streamability':'streamable','interface_family':'native','design_requirements':{'target':'rtl','pipeline_required':True,'streamability':'streamable','interface_family':'native','interface_profile':{},'confirmed_by_user':True},'interfaces':{'ports':[{'name':'i_clk','direction':'input','width':1,'role':'clock'},{'name':'i_rstn','direction':'input','width':1,'role':'reset'}]},'clock':{'name':'i_clk','edge':'posedge','frequency_mhz':1562.5},'reset':{'name':'i_rstn','active':'low','synchronous':True},'outputs':[{'path':'tl_tx_buffered.v','kind':'rtl'}]}
(S/'skill_spec.json').write_text(json.dumps(spec,indent=2)+'\n');r=validate_verilog_artifacts(spec,D,run_external=False,readiness='static',report_json=S/'skill_gate.json');print(json.dumps(r,ensure_ascii=False));analyze_existing_verilog(R/'rtl/tl/tl_tx_buffered.v',out_dir=S/'analysis',module_name='tl_tx_buffered');raise SystemExit(0 if r['ok'] else 1)

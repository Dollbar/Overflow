"""Parse complete actual-top STA measurements, preserving negative timing.
Used by run_physical.py; qualify with test_timing_report.py before auditing logs.
Successful measurement is separate from closure and from real macro signoff.
"""
import math
import re

PATHS={'input_to_register','register_to_register','register_to_output','register_to_macro','input_to_macro','macro_to_register'}


def need(condition,message):
    if not condition:raise ValueError(message)


def measure(text,*,width,view,period,exit_code):
    need(width in (8,16) and view in ('fast','typical','slow') and period in ('0.640','6.400'),'invalid profile')
    need(not re.search(r'^\s*(?:Warning:|Error:)|\bunconstrained\b',text,re.M|re.I),'tool diagnostic or unconstrained path')
    def exact(pattern,expected):need(re.findall(pattern,text,re.M)==[expected],'missing or ambiguous '+pattern)
    exact(r'^TX_PREPARED_PROFILE width=(\d+) header_depth=(\d+) bank_depth=(\d+) macro_view=(\S+) period_ns=(\S+)$',(str(width),'2','3',view,period))
    exact(r'^TX_PREPARED_LIBRARY name=(\S+)$','kd28_sram_'+view)
    exact(r'^TX_PREPARED_MACRO cell=(\S+) count=(\d+)$',('KD28_SRAM_SDP_256X32','64'))
    exact(r'^TX_PREPARED_PINS write_clocks=(\d+) read_clocks=(\d+) read_outputs=(\d+) write_data=(\d+) read_address=(\d+) write_address=(\d+)$',('64','64','2048','2048','512','512'))
    slacks={}
    for kind,name in (('max','setup_slack_ns'),('min','hold_slack_ns')):
        values=re.findall(rf'^worst slack {kind}\s+(\S+)\s*$',text,re.M)
        need(len(values)==1,'missing global slack');value=float(values[0]);need(math.isfinite(value),'nonfinite global slack');slacks[name]=value
    paths={}
    for name,minimum,maximum in re.findall(r'^TX_PREPARED_PATH (\S+) min_slack_ns=(\S+) max_slack_ns=(\S+)$',text,re.M):
        need(name not in paths,'duplicate path class');entry=dict(hold_slack_ns=float(minimum),setup_slack_ns=float(maximum))
        need(all(math.isfinite(v) and v+0.000002>=slacks[k] for k,v in entry.items()),'nonfinite/inconsistent path slack');paths[name]=entry
    need(set(paths)==PATHS,'missing actual path families')
    need(text.count('TX_PREPARED_COMPLETE actual_cells=1 synthetic_memory=1')==1,'incomplete measurement')
    negative=min(slacks.values())< -0.000001
    if negative:
        need(exit_code==1 and text.count('FAIL tx_prepared STA: Negative setup or hold slack')==1 and 'PASS tx_prepared' not in text,'negative result misclassified')
    else:
        need(exit_code==0 and f'PASS tx_prepared setup/hold at period_ns={period}; synthetic macro budget only' in text and not re.search(r'^FAIL',text,re.M),'missing successful budget result')
    closed=not negative and min(slacks.values())>=0 and '(VIOLATED)' not in text
    return dict(slacks,paths=paths,measurement_complete=True,timing_closed=closed,
                scope='actual standard cells with synthetic SRAM, prelayout only')

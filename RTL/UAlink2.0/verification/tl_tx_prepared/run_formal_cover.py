"""Run: python3 verification/tl_tx_prepared/run_formal_cover.py --label ownership_cover
[--parent ownership_final] [--impossible]. Requires completed parent WIDTH 8/16,
depth 1 proof graphs. Outputs SAT witnesses/logs in tl_tx_prepared/LABEL.
Reach both lanes capturing a replacement while their final old partition queues,
then full-queue stalls and synchronous cancellation of owned and queued groups.
Next combine reachability with unbounded invariants; no memory data signoff.
"""
from pathlib import Path
import argparse
import json
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--label',required=True);p.add_argument('--parent',default='ownership_final')
    p.add_argument('--widths',type=int,nargs='+',choices=(8,16),default=[8,16])
    p.add_argument('--impossible',action='store_true');a=p.parse_args()
    for x in (a.label,a.parent):need(x.replace('_','').replace('-','').isalnum(),'invalid label')
    base=ROOT/'build/verification/tl_tx_prepared';stage=base/a.label;stage.mkdir(exist_ok=False)
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    report=dict(complete=False,parent=a.parent,impossible=a.impossible,results=[])
    for width in a.widths:
        source=base/a.parent/f'w{width}_d1/proof.json';need(source.is_file(),'missing parent proof graph')
        folder=stage/f'w{width}';folder.mkdir()
        constraints={3:dict(o_source_captured=3,o_group_queued=3),
                     4:dict(i_rstn=1,f_owned_0=1,f_owned_1=1,o_header_count=3,o_partition_taken=0),
                     5:dict(i_rstn=0),6:dict(i_rstn=1,f_owned_0=0,f_owned_1=0,o_header_count=0)}
        if a.impossible:constraints[3]['i_source_tags_valid']=0
        options=' '.join(f'-set-at {step} {name} {value}' for step,values in constraints.items() for name,value in values.items())
        signals='i_rstn,i_auth,i_taken,i_source_tags_valid,o_source_ready,o_source_captured,o_group_queued,o_partition_taken,o_header_count,f_owned_0,f_owned_1'
        script=f'read_json "{source}"\nhierarchy -top properties\ncheck -assert\nsat -seq 6 -set-assumes -set i_auth 1 -set i_taken 0 {options} -show {signals} -dump_json "{folder}/witness.json"\n'
        (folder/'cover.ys').write_text(script)
        run=execute(['yosys','-Q','-T','-s',str(folder/'cover.ys')],folder/'cover.log',120)
        log=(folder/'cover.log').read_text()
        found=run['exit']==0 and 'SAT solving finished - model found:' in log and (folder/'witness.json').is_file()
        excluded=run['exit']==0 and 'SAT solving finished - no model found.' in log
        row=dict(width=width,proof_graph=str(source),proof_graph_sha256=sha(source),run=run,witness=found,excluded=excluded)
        report['results'].append(row);dump(stage/'results.json',report);print(row,flush=True)
    report['complete']=len(report['results'])==len(a.widths) and all(r['excluded'] if a.impossible else r['witness'] for r in report['results'])
    dump(stage/'results.json',report);return 0 if report['complete'] else 1


if __name__=='__main__':raise SystemExit(main())

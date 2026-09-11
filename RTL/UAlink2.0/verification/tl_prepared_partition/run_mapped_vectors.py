"""Run: python3 verification/tl_prepared_partition/run_mapped_vectors.py
--parent actual_relation --label mapped_vectors [--widths 8 16]
[--expect-mismatch] [--seconds 600]. Replays the independent streaming oracle vectors on the
actual mapped Verilog with Boolean/sequential models imported from its recorded
Liberty. Outputs private generated models, snapshots, expected/actual traces and
real simulation logs. This is digital functionality, not cell timing simulation.
Next audit with mapped CEC and reset evidence.
"""
from pathlib import Path
import argparse
import json
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parent',required=True);p.add_argument('--label',required=True)
    p.add_argument('--widths',type=int,nargs='+',choices=(8,16),default=[8,16]);p.add_argument('--expect-mismatch',action='store_true')
    p.add_argument('--seconds',type=int,default=600);a=p.parse_args();need(a.seconds>0,'positive simulation budget')
    for label in (a.parent,a.label):need(label.replace('_','').replace('-','').isalnum(),'invalid label')
    base=ROOT/'build/verification/tl_prepared_mapping';parent=base/a.parent;record=json.loads((parent/'results.json').read_text())
    library=Path(record['library']['path']);need(sha(library)==record['library']['sha256'],'exact recorded Liberty')
    stage=base/a.label;stage.mkdir(exist_ok=False);(stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    unit=ROOT/'build/verification/tl_prepared_partition/unit_semantics';oracle=json.loads((unit/'results.json').read_text());need(oracle['complete'],'complete independent unit oracle')
    script=f'yosys read_liberty -ignore_miss_func {{{library}}}\nyosys write_verilog -noattr {{{stage}/cells.v}}\n';(stage/'models.tcl').write_text(script)
    models=execute(['yosys','-Q','-T','-c',str(stage/'models.tcl')],stage/'models.log',60)
    need(models['exit']==0,'actual Liberty Boolean/sequential model export')
    result=dict(complete=False,parent=a.parent,expect_mismatch=a.expect_mismatch,library=record['library'],oracle_report_sha256=sha(unit/'results.json'),models=models,models_sha256=sha(stage/'cells.v'),scope='actual mapped digital logic against independent oracle; no delay or analog claims',results=[])
    for width in a.widths:
        folder=stage/f'w{width}';folder.mkdir();source=parent/f'w{width}'/'mapped.v';snapshot=next(r for r in record['results'] if r['width']==width)
        need(sha(source)==snapshot['netlist_sha256'],'exact mapped netlist')
        (folder/'mapped.v').write_bytes(source.read_bytes());fixture=unit/f'w{width}'
        for name in ('vectors.hex','expected.hex'):(folder/name).write_bytes((fixture/name).read_bytes())
        tb=(fixture/'tb.sv').read_text().replace(f'tl_prepared_partition #(.WIDTH({width}))','tl_prepared_partition').replace(str(fixture),str(folder));(folder/'tb.sv').write_text(tb)
        compile_result=execute(['iverilog','-g2012','-s','tb','-o',str(folder/'sim.vvp'),str(folder/'mapped.v'),str(stage/'cells.v'),str(folder/'tb.sv')],folder/'compile.log',120)
        row=dict(width=width,netlist_sha256=sha(source),compile=compile_result,passed=False);result['results'].append(row);dump(stage/'results.json',result)
        if compile_result['exit']:continue
        run=execute(['vvp',str(folder/'sim.vvp')],folder/'run.log',a.seconds);log=(folder/'run.log').read_text()
        passed=(run['exit'] not in (0,124) and 'FATAL:' in log and 'prepared vector' in log) if a.expect_mismatch else (run['exit']==0 and 'PASS prepared' in log)
        row.update(run=run,passed=passed);dump(stage/'results.json',result);print(width,passed,run,flush=True)
    result['complete']=len(result['results'])==len(a.widths) and all(r['passed'] for r in result['results']);dump(stage/'results.json',result)
    return 0 if result['complete'] else 1


if __name__=='__main__':raise SystemExit(main())

"""Run python3 verification/tl_prepared_partition/run_miter_vectors.py
--miter-label NAME --label NAME [--expect-mismatch]. Replays the independent unit
stimuli on the actual uncut two-machine RTL miter. Baseline outputs must equal
the oracle at every checked edge, including negative runs. Outputs actual paired
traces and reset-to-failure witnesses; next audit alongside the formal step proof.
"""
from pathlib import Path
import argparse
import json
import re
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--miter-label',required=True);parser.add_argument('--label',required=True)
    parser.add_argument('--expect-mismatch',action='store_true')
    args=parser.parse_args()
    for name in (args.miter_label,args.label):need(name.replace('_','').replace('-','').isalnum(),'invalid label')
    base=ROOT/'build/verification/tl_prepared_equivalence';source=base/args.miter_label;stage=base/args.label;stage.mkdir(parents=True,exist_ok=False)
    parent=json.loads((source/'results.json').read_text());unit=ROOT/'build/verification/tl_prepared_partition/unit_semantics'
    result=dict(complete=False,miter_label=args.miter_label,miter_report_sha256=sha(source/'results.json'),expect_mismatch=args.expect_mismatch,results=[])
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    for config in parent['results']:
        width=config['width'];folder=stage/f'w{width}';folder.mkdir();fixture=unit/f'w{width}'
        for name in ('vectors.hex','expected.hex'):(folder/name).write_bytes((fixture/name).read_bytes())
        original=(fixture/'tb.sv').read_text();parts=re.findall(r'\.i_(\w+)\(v\[(\d+)\+:(\d+)\]\)',original)
        need(len(parts)==10,'all ten non-clock input ports')
        bits=max(int(offset)+int(size) for _,offset,size in parts);count=len((folder/'vectors.hex').read_text().splitlines())
        connections=','.join(f'.i_{name}(v[{offset}+:{size}])' for name,offset,size in parts)
        tb=f'''module tb;
reg clk=0;always #5 clk=~clk;reg [{bits-1}:0] v,vectors[0:{count-1}];reg [530:0] expected[0:{count-1}];wire bad;integer j,fd;
miter dut(.i_clk(clk),{connections},.o_bad(bad));
initial begin $readmemh("{folder}/vectors.hex",vectors);$readmemh("{folder}/expected.hex",expected);fd=$fopen("{folder}/paired_trace.txt","w");for(j=0;j<{count};j=j+1)begin @(negedge clk);v=vectors[j];#1;$fdisplay(fd,"%0d %h %h %b",j,dut.gold_outputs,dut.gate_outputs,bad);if(dut.gold_outputs!==expected[j])$fatal(1,"reference oracle mismatch vector %0d",j);if(bad!== (|(dut.gold_outputs^dut.gate_outputs)))$fatal(1,"incorrect miter wiring");if(bad!==1'b0)$fatal(1,"miter mismatch vector %0d gold=%h gate=%h",j,dut.gold_outputs,dut.gate_outputs);end @(negedge clk);$fclose(fd);$display("PASS full miter WIDTH={width} vectors={count}");$finish;end
endmodule
'''
        (folder/'tb.sv').write_text(tb)
        sources=sorted((source/'compiled').glob('*.v'))+[source/f'w{width}'/'miter.v',folder/'tb.sv']
        compiled=execute(['iverilog','-g2012','-s','tb','-o',str(folder/'sim.vvp'),*map(str,sources)],folder/'compile.log',120)
        row=dict(width=width,compile=compiled,passed=False,sources={str(p):sha(p) for p in sources})
        if compiled['exit']==0:
            run=execute(['vvp',str(folder/'sim.vvp')],folder/'run.log',180);log=(folder/'run.log').read_text()
            success=run['exit'] not in (0,124) and 'miter mismatch vector ' in log if args.expect_mismatch else run['exit']==0 and 'PASS full miter' in log
            row.update(run=run,passed=success)
        result['results'].append(row);dump(stage/'results.json',result);print(width,row['passed'],flush=True)
    result['complete']=bool(result['results']) and all(r['passed'] for r in result['results']);dump(stage/'results.json',result)
    return 0 if result['complete'] else 1


if __name__=='__main__':
    raise SystemExit(main())

"""Run: python3 verification/tl_prepared_partition/run_cost_lemma.py --candidate FILE --label NAME.
Extracts the actual carry-save cost block and proves all eight six-bit prefixes
against independent modulo sums for 48 arbitrary contribution bits. Outputs
candidate snapshot, full miter/SAT log/witness in build/verification/tl_cost_compression/NAME.
Next run whole-module equivalence and actual TSMC28 timing; a passing arithmetic
lemma alone does not establish module equivalence or timing improvement.
"""
from pathlib import Path
import argparse
import re
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import need,dump,execute,sha


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--candidate',type=Path,required=True);p.add_argument('--label',required=True);p.add_argument('--legacy',action='store_true',help='prove original balanced prefix block');a=p.parse_args()
    need(a.label.replace('_','').replace('-','').isalnum(),'invalid label')
    folder=ROOT/'build/verification/tl_cost_compression'/a.label;folder.mkdir(parents=True,exist_ok=False)
    (folder/'runner.py').write_bytes(Path(__file__).read_bytes())
    source=a.candidate.read_text();(folder/'candidate.v').write_bytes(a.candidate.read_bytes())
    if a.legacy:
        start=source.index(' assign pair[0]=');end=source.index('end endgenerate // 结束复用费用',start)
        body='wire [5:0] pair[0:3];wire [5:0] quad[0:1];\n'+source[start:end]
    else:
        found=re.findall(r'// BEGIN_COST_COMPRESSION\n(.*?)// END_COST_COMPRESSION',source,re.S)
        need(len(found)==1,'missing unique actual cost compression block')
        body=found[0]
    need(len(re.findall(r'assign prefix_cost\[',body))==8,'all actual prefix assignments')
    code=['module cost(input [47:0] values,output o_bad);localparam account=0;wire [5:0] contribution[0:7];wire [47:0] prefix_cost,expected;']
    for i in range(8):
        code += [f'assign contribution[{i}]=values[{6*i}+:6];',f'assign expected[{6*i}+:6]='+'+'.join(f'values[{6*j}+:6]' for j in range(i+1))+';']
    code += [body,'assign o_bad=(prefix_cost!=expected);endmodule']
    (folder/'proof.v').write_text('\n'.join(code)+'\n')
    (folder/'proof.ys').write_text(f'read_verilog "{folder}/proof.v"\nprep -top cost\ncheck -assert\nsat -prove o_bad 0 -verify -dump_json "{folder}/witness.json"\n')
    proof=execute(['yosys','-Q','-T','-s',str(folder/'proof.ys')],folder/'proof.log',120)
    passed=proof['exit']==0 and 'SAT proof finished - no model found: SUCCESS!' in (folder/'proof.log').read_text()
    result=dict(complete=passed,candidate_sha256=sha(a.candidate),input_bits=48,output_bits=48,legacy=a.legacy,assumptions=[],proof=proof)
    dump(folder/'results.json',result);print(result);return 0 if passed else 1


if __name__=='__main__':raise SystemExit(main())

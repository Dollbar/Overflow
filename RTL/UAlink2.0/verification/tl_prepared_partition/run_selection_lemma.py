"""Run: python3 verification/tl_prepared_partition/run_selection_lemma.py
--candidate FILE --label NAME. Proves the actual candidate's sector/tag mask
assignments against longest-fit selection for all 2^20 application/cursor/fit
combinations. No protocol-validity assumption is used. Outputs source snippets,
full SAT miter/log/witness under build/verification/tl_selection_reduction/NAME.
Next full sequential-output/state CEC and physical measurement.
"""
from pathlib import Path
import argparse
import re
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--candidate',type=Path,required=True);p.add_argument('--label',required=True);a=p.parse_args()
    need(a.label.replace('_','').replace('-','').isalnum(),'invalid label')
    stage=ROOT/'build/verification/tl_selection_reduction'/a.label;stage.mkdir(parents=True,exist_ok=False)
    need(a.candidate.is_file(),'actual candidate missing; selection test precedes implementation')
    source=a.candidate.read_text();snippets=[]
    for expression in (r'assign selected_sectors\[sector\]=[^;]+;',r'assign tag_eligible\[boundary\]=[^;]+;',r'assign selected_tags\[tag\]=[^;]+;'):
        matches=re.findall(expression,source);need(len(matches)==1,'unique actual selection equation');snippets.append(matches[0])
    code=['module selection(input [7:0] r_application,fit,input [3:0] r_cursor,output o_bad);',
          'wire [3:0] prefix_fields[0:7];wire [7:0] selected_sectors;wire [3:0] selected_tags;']
    for boundary in range(8):
        terms=[f"((r_application[{i}]&&(r_cursor<=4'd{i}))?4'd1:4'd0)" for i in range(boundary+1)]
        code += [f'assign prefix_fields[{boundary}]='+ '+'.join(terms)+';']
    code += ['genvar sector,tag,boundary;generate for(sector=0;sector<8;sector=sector+1)begin:sec localparam [3:0] POSITION=sector;',snippets[0],'end',
             'for(tag=0;tag<4;tag=tag+1)begin:tags localparam [3:0] TAG_POSITION=tag;wire [7:0] tag_eligible;',
             'for(boundary=0;boundary<8;boundary=boundary+1)begin:bounds',snippets[1],'end',snippets[2],'end endgenerate',
             'integer b;reg [3:0] chosen_end,chosen_fields;reg [7:0] expected_sectors;reg [3:0] expected_tags;',
             'always @* begin chosen_end=0;chosen_fields=0;expected_sectors=0;expected_tags=0;',
             'for(b=0;b<8;b=b+1)if(fit[b])begin chosen_end=b+1;chosen_fields=prefix_fields[b];end',
             'for(b=0;b<8;b=b+1)expected_sectors[b]=(r_cursor<=b)&&(b<chosen_end);',
             'for(b=0;b<4;b=b+1)expected_tags[b]=(b<chosen_fields);end',
             'assign o_bad=(selected_sectors!=expected_sectors)||(selected_tags!=expected_tags);endmodule']
    (stage/'proof.v').write_text('\n'.join(code)+'\n');(stage/'candidate.v').write_bytes(a.candidate.read_bytes())
    script=f'read_verilog "{stage}/proof.v"\nprep -top selection\ncheck -assert\nsat -prove o_bad 0 -verify -dump_json "{stage}/witness.json"\n';(stage/'proof.ys').write_text(script)
    proof=execute(['yosys','-Q','-T','-s',str(stage/'proof.ys')],stage/'proof.log',60)
    passed=proof['exit']==0 and 'SAT proof finished - no model found: SUCCESS!' in (stage/'proof.log').read_text()
    result=dict(complete=passed,candidate_sha256=sha(a.candidate),combinations=1<<20,public_mask_bits=12,protocol_assumptions=[],proof=proof)
    dump(stage/'results.json',result);print(result)
    return 0 if passed else 1


if __name__=='__main__':raise SystemExit(main())

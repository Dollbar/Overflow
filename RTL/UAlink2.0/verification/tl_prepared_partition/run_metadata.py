"""Run python3 verification/tl_prepared_partition/run_metadata.py [--label metadata]
[--widths 8 16] [--candidate FILE]. Proves actual captured metadata equals the
immutable baseline decoder applied to the held raw word, while owned. Outputs
instrumented sources and inductive SAT logs/witnesses in tl_prepared_equivalence.
Next use this proved relation, with cursor/ownership invariants, in full equivalence.
No production state or output is cut, assumed equal, or overridden.
"""
from pathlib import Path
import argparse
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha
from run_reference import REFERENCE

PROPERTIES='''
wire [7:0] p_starts,p_app,p_bad_fc;wire [31:0] p_counts;wire [39:0] p_slots;
wire p_valid;wire [1:0] p_status;wire [3:0] p_fields,p_responses;wire [2:0] p_requests;
reg f_response;reg f_past_valid=0;
tl_metadata_probe #(.WIDTH(WIDTH)) Metadata_Reference_Inst(
 .i_rstn(1'b1),.i_control(1'b1),.i_done(1'b1),.i_shared(1'b0),.i_half(r_control),
 .i_available({20*(WIDTH+1){1'b0}}),.i_capacity({20*(WIDTH+1){1'b0}}),
 .o_requirements(),.o_allow(),.o_wait(),.o_shortfall(),.p_starts(p_starts),.p_app(p_app),.p_counts(p_counts),.p_slots(p_slots),
 .p_valid(p_valid),.p_status(p_status),.p_fields(p_fields),.p_requests(p_requests),.p_responses(p_responses));
genvar p_sector;generate for(p_sector=0;p_sector<8;p_sector=p_sector+1)begin:gen_probe_fc
 assign p_bad_fc[p_sector]=p_starts[p_sector]&&!p_app[p_sector]&&(r_control[p_sector*32+:32]!=0);
end endgenerate
wire p_error=!p_valid||(p_status!=0)||(p_fields==0)||(f_response?(p_requests!=0):(p_responses!=0))||(|p_bad_fc);
always @(posedge i_clk)begin
 f_past_valid<=1;
 if(!f_past_valid)assume(!i_rstn);
 if(o_captured)f_response<=i_response;
 if(f_past_valid&&r_owned)begin
  assert(r_starts==p_starts[7:1]);assert(r_application==p_app);
  assert(r_counts==p_counts);assert(r_slots==p_slots);assert(r_error==p_error);
 end
end
'''


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label',default='metadata')
    parser.add_argument('--widths',type=int,nargs='+',choices=range(8,17),default=[8,16])
    parser.add_argument('--candidate',type=Path,default=ROOT/'rtl/tl/tl_prepared_partition.v')
    args=parser.parse_args();need(args.label.replace('_','').replace('-','').isalnum(),'invalid label')
    stage=ROOT/'build/verification/tl_prepared_equivalence'/args.label;stage.mkdir(parents=True,exist_ok=False)
    source=args.candidate.resolve();(stage/'candidate.v').write_bytes(source.read_bytes());need(source.read_text().count('endmodule')==1,'one candidate module')
    (stage/'proof.sv').write_text(source.read_text().replace('endmodule',PROPERTIES+'\nendmodule'))
    baseline=subprocess.check_output(['git','show',REFERENCE+':rtl/tl/tl_credit_admission.v'],cwd=ROOT).decode()
    (stage/'baseline_admission.v').write_text(baseline)
    anchor='output wire o_allow,o_wait,o_shortfall';need(baseline.count(anchor)==1,'baseline observation port anchor')
    ports=',output wire [7:0] p_starts,p_app,output wire [31:0] p_counts,output wire [39:0] p_slots,output wire p_valid,output wire [1:0] p_status,output wire [3:0] p_fields,p_responses,output wire [2:0] p_requests'
    probe=baseline.replace('module tl_credit_admission #','module tl_metadata_probe #').replace(anchor,anchor+ports)
    observations='assign p_starts=unused_starts;assign p_app=w_req|w_rsp;assign p_counts=w_counts;assign p_slots=w_slots;assign p_valid=valid;assign p_status=status;assign p_fields=unused_fields;assign p_requests=unused_requests;assign p_responses=unused_responses;\n'
    (stage/'probe.v').write_text(probe.replace('endmodule',observations+'endmodule'))
    dependencies=[]
    for name in ('tl_control_decode.v','tl_control_tenure.v'):
        current=ROOT/'rtl/tl'/name;old=subprocess.check_output(['git','show',REFERENCE+':rtl/tl/'+name],cwd=ROOT)
        need(current.read_bytes()==old,'shared probe decoder changed since immutable baseline')
        p=stage/name;p.write_bytes(old);dependencies.append(current)
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    result=dict(complete=False,reference=REFERENCE,sources={str(p):sha(p) for p in (source,*dependencies)},observations='actual baseline admission signals; no signal cuts',results=[])
    for width in args.widths:
        folder=stage/f'w{width}';folder.mkdir()
        sources=' '.join('"'+str(stage/n)+'"' for n in ('proof.sv','probe.v','tl_control_decode.v','tl_control_tenure.v'))
        script=f'read_verilog -formal -sv {sources}\nchparam -set WIDTH {width} tl_prepared_partition\nprep -top tl_prepared_partition -flatten\ncheck -assert\nwrite_json "{folder}/structure.json"\nsat -seq 2 -tempinduct -maxsteps 4 -set-assumes -prove-asserts -verify -dump_json "{folder}/witness.json"\n'
        (folder/'proof.ys').write_text(script)
        proof=execute(['yosys','-Q','-T','-s',str(folder/'proof.ys')],folder/'proof.log',180)
        log=(folder/'proof.log').read_text();row=dict(width=width,proof=proof,passed=proof['exit']==0 and 'Induction step proven: SUCCESS!' in log)
        result['results'].append(row);dump(stage/'results.json',result);print(width,row['passed'],proof,flush=True)
    result['complete']=len(result['results'])==len(args.widths) and all(r['passed'] for r in result['results'])
    result['sources_unchanged']=all(sha(p)==result['sources'][str(p)] for p in (source,*dependencies));result['complete'] &= result['sources_unchanged']
    dump(stage/'results.json',result)
    return 0 if result['complete'] else 1


if __name__=='__main__':
    raise SystemExit(main())

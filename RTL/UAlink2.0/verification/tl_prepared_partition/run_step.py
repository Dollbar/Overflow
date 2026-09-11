"""Run python3 verification/tl_prepared_partition/run_step.py [--label step]
[--widths 8 16] [--candidate FILE] [--prepare-only]. Checks the relation-preserving complete output
and next-state step, plus unconditional reset base, using real FF D/Q equations.
Every state bit is inventoried; metadata/owned-cursor relations are explicit and
must be joined with their separately proved reachable invariants before claiming
sequential equivalence. Outputs cut inventories, miter, SAT logs and witnesses in
build/verification/tl_prepared_equivalence/LABEL. Next audit the proof composition.
"""
from pathlib import Path
import argparse
import copy
import json
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha
from run_reference import REFERENCE,DEPENDENCIES
from run_equivalence import OUTPUTS

SHARED=('owned','cursor','control','tags','capacity','auth','shared','response')
GATE_FIELDS=dict(owned='r_owned',cursor='r_cursor',control='r_control',tags='r_tags',capacity='r_capacity',auth='r_auth',shared='r_shared',response='proof_response',error='r_error',starts='r_starts',application='r_application',counts='r_counts',slots='r_slots')
GOLD_FIELDS=dict(owned='held_valid',cursor='Raw_Reference_Inst.r_cursor',control='held_control',tags='held_tags',capacity='held_capacity',auth='held_auth',shared='held_shared',response='held_response')


def cut_state(original,fields,top):
    graph=copy.deepcopy(original);clock=graph['ports']['i_clk']['bits'];drivers={};remove=[]
    for name,cell in graph['cells'].items():
        need('latch' not in cell['type'].lower(),'latch in real state inventory')
        if cell['type']=='$dff':
            need(cell['connections']['CLK']==clock and int(cell['parameters']['CLK_POLARITY'],2)==1,'real clock mismatch')
            need(len(cell['connections']['D'])==len(cell['connections']['Q']),'FF width')
            for q,d in zip(cell['connections']['Q'],cell['connections']['D']):
                need(isinstance(q,int) and q not in drivers,'duplicate FF driver');drivers[q]=d
            remove.append(name)
    layout={};covered=set()
    for field,name in fields.items():
        bits=graph['netnames'][name]['bits']
        need(all(isinstance(b,int) and b in drivers and b not in covered for b in bits),'state vector not unique real FF Q: '+name)
        covered.update(bits);layout[field]=dict(net=name,width=len(bits),q=bits,d=[drivers[b] for b in bits])
        graph['ports']['s_'+field]=dict(direction='input',bits=bits)
        graph['ports']['n_'+field]=dict(direction='output',bits=[drivers[b] for b in bits])
    need(covered==set(drivers),'unclassified real state bits')
    for name in remove:del graph['cells'][name]
    graph['attributes'].pop('top',None)
    return dict(modules={top:graph}),dict(state_bits=len(covered),clock=clock,fields=layout,unclassified_state_bits=0)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label',default='step')
    parser.add_argument('--widths',type=int,nargs='+',choices=range(8,17),default=[8,16])
    parser.add_argument('--candidate',type=Path,default=ROOT/'rtl/tl/tl_prepared_partition.v')
    parser.add_argument('--prepare-only',action='store_true',help='emit exact miter/inventories for separate exhaustive cursor cases')
    args=parser.parse_args();need(args.label.replace('_','').replace('-','').isalnum(),'invalid label')
    stage=ROOT/'build/verification/tl_prepared_equivalence'/args.label;stage.mkdir(parents=True,exist_ok=False)
    candidate=args.candidate.resolve();reference=Path(__file__).with_name('reference.v')
    (stage/'original_candidate.v').write_bytes(candidate.read_bytes())
    ghost="(* keep = 1 *) reg proof_response;always @(posedge i_clk)if(o_captured)proof_response<=i_response;\n"
    need(candidate.read_text().count('endmodule')==1,'one candidate module')
    (stage/'candidate.v').write_text(candidate.read_text().replace('endmodule',ghost+'endmodule'))
    (stage/'reference.v').write_bytes(reference.read_bytes())
    for name in DEPENDENCIES:(stage/name).write_bytes(subprocess.check_output(['git','show',REFERENCE+':rtl/tl/'+name],cwd=ROOT))
    for name in ('tl_control_decode.v','tl_control_tenure.v'):need((stage/name).read_bytes()==(ROOT/'rtl/tl'/name).read_bytes(),'candidate dependency drift')
    metadata=ROOT/'build/verification/tl_prepared_equivalence/metadata'
    need(json.loads((metadata/'results.json').read_text())['complete'],'proved metadata relation required')
    (stage/'probe.v').write_bytes((metadata/'probe.v').read_bytes())
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    result=dict(complete=False,reference=REFERENCE,sources={str(p.resolve()):sha(p) for p in (candidate,reference,ROOT/'rtl/tl/tl_control_decode.v',ROOT/'rtl/tl/tl_control_tenure.v')},composition_required=True,metadata_lemma_sha256=sha(metadata/'results.json'),public_output_bits=531,results=[])
    for width in args.widths:
        folder=stage/f'w{width}';folder.mkdir();layouts={}
        for side,top,fields in (('gold','tl_prepared_reference',GOLD_FIELDS),('gate','tl_prepared_partition',GATE_FIELDS)):
            names=['reference.v',*DEPENDENCIES] if side=='gold' else ['candidate.v','tl_control_decode.v','tl_control_tenure.v']
            sources=' '.join('"'+str(stage/n)+'"' for n in names)
            script=f'read_verilog {sources}\nchparam -set WIDTH {width} {top}\nprep -top {top} -flatten\ncheck -assert\nwrite_json "{folder}/{side}_original.json"\n'
            (folder/f'{side}_prepare.ys').write_text(script)
            code=execute(['yosys','-Q','-T','-s',str(folder/f'{side}_prepare.ys')],folder/f'{side}_prepare.log',120)
            need(code['exit']==0,'real source preparation '+side)
            original=json.loads((folder/f'{side}_original.json').read_text())['modules'][top]
            need({n:len(p['bits']) for n,p in original['ports'].items() if p['direction']=='output'}==OUTPUTS,'full public outputs '+side)
            transformed,layout=cut_state(original,fields,'step_'+side)
            dump(folder/f'{side}_cut.json',transformed);dump(folder/f'{side}_state.json',layout);layouts[side]=layout
        widths={name:item['width'] for name,item in layouts['gate']['fields'].items()}
        live=dict(i_clk=1,i_rstn=1,i_source_valid=1,i_ready=1,i_done=1,i_response=1,i_auth=1,i_shared=1,i_source_control=256,i_source_tags=512,i_capacity=20*(width+1))
        inputs=dict(live,**{'h_'+n:widths[n] for n in SHARED})
        for side in ('gold','gate'):
            inputs.update({f'e_{side}_{n}':item['width'] for n,item in layouts[side]['fields'].items()})
        declarations=','.join(f'input wire [{b-1}:0] {n}' for n,b in inputs.items())
        code=[f'module step({declarations},output wire o_bad);']
        code+=['wire [7:0] p_starts,p_app,p_bad_fc;wire [31:0] p_counts;wire [39:0] p_slots;wire p_valid;wire [1:0] p_status;wire [3:0] p_fields,p_responses;wire [2:0] p_requests;']
        code+=[f"tl_metadata_probe #(.WIDTH({width})) probe(.i_rstn(1'b1),.i_control(1'b1),.i_done(1'b1),.i_shared(1'b0),.i_half(h_control),.i_available({20*(width+1)}'d0),.i_capacity({20*(width+1)}'d0),.o_requirements(),.o_allow(),.o_wait(),.o_shortfall(),.p_starts(p_starts),.p_app(p_app),.p_counts(p_counts),.p_slots(p_slots),.p_valid(p_valid),.p_status(p_status),.p_fields(p_fields),.p_requests(p_requests),.p_responses(p_responses));"]
        code+=['genvar sector;generate for(sector=0;sector<8;sector=sector+1)begin:fc assign p_bad_fc[sector]=p_starts[sector]&&!p_app[sector]&&(h_control[sector*32+:32]!=0);end endgenerate']
        code+=['wire p_error=!p_valid||(p_status!=0)||(p_fields==0)||(h_response?(p_requests!=0):(p_responses!=0))||(|p_bad_fc);']
        metadata_values=dict(error='p_error',starts='p_starts[7:1]',application='p_app',counts='p_counts',slots='p_slots')
        for side in ('gold','gate'):
            code += [f'wire [530:0] {side}_outputs;']
            connections=[f'.{n}({n})' for n in live];shift=0
            for name,bits in OUTPUTS.items():connections.append(f'.{name}({side}_outputs[{shift}+:{bits}])');shift+=bits
            for field,item in layouts[side]['fields'].items():
                bits=item['width'];value='h_'+field if field in SHARED else metadata_values[field]
                cond='i_rstn' if field in ('owned','cursor') else 'i_rstn&&h_owned'
                code += [f'wire [{bits-1}:0] {side}_s_{field}=({cond})?{value}:e_{side}_{field};wire [{bits-1}:0] {side}_n_{field};']
                connections += [f'.s_{field}({side}_s_{field})',f'.n_{field}({side}_n_{field})']
            code += [f'step_{side} {side}('+','.join(connections)+');']
        raw_diff='||'.join(f'(gold_n_{n}!=gate_n_{n})' for n in SHARED if n not in ('owned','cursor'))
        code+=['wire relation_next_bad=(gold_n_owned!=gate_n_owned)||(gold_n_cursor!=gate_n_cursor)||(gold_n_owned&&('+raw_diff+'));']
        code+=['wire domain=(!h_owned&&(h_cursor==0))||(h_owned&&(h_cursor<8)&&(p_error||(h_cursor==0)||p_starts[h_cursor]));']
        code+=['wire reset_bad=!i_rstn&&((|gold_outputs)||(|gate_outputs)||gold_n_owned||gate_n_owned||(gold_n_cursor!=0)||(gate_n_cursor!=0));']
        code+=['assign o_bad=reset_bad||(i_rstn&&domain&&((|(gold_outputs^gate_outputs))||relation_next_bad));','endmodule']
        (folder/'step.v').write_text('\n'.join(code)+'\n')
        script=f'read_json "{folder}/gold_cut.json" "{folder}/gate_cut.json"\nread_verilog "{stage}/probe.v" "{stage}/tl_control_decode.v" "{stage}/tl_control_tenure.v" "{folder}/step.v"\nprep -top step -flatten\ncheck -assert\nwrite_json "{folder}/step_structure.json"\n'
        if not args.prepare_only:script+=f'sat -prove o_bad 0 -verify -dump_json "{folder}/witness.json"\n'
        (folder/'proof.ys').write_text(script)
        proof=execute(['yosys','-Q','-T','-s',str(folder/'proof.ys')],folder/'proof.log',240)
        log=(folder/'proof.log').read_text();row=dict(width=width,proof=proof,prepared=(folder/'step_structure.json').is_file(),prepare_only=args.prepare_only,gate_state_bits=layouts['gate']['state_bits'],gold_state_bits=layouts['gold']['state_bits'],passed=proof['exit']==0 and 'SAT proof finished - no model found: SUCCESS!' in log)
        result['results'].append(row);dump(stage/'results.json',result);print(width,row['passed'],proof,flush=True)
    result['complete']=len(result['results'])==len(args.widths) and all(r['passed'] for r in result['results'])
    dump(stage/'results.json',result)
    return 0 if result['complete'] or (args.prepare_only and all(r['proof']['exit']==0 and r['prepared'] for r in result['results'])) else 1


if __name__=='__main__':
    raise SystemExit(main())

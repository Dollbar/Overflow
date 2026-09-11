"""Run python3 verification/tl_prepared_partition/run_equivalence.py [--label rtl]
[--widths 8 16] [--candidate FILE] [--seconds 180] [--prepare-only]. Builds an uncut, two-machine
post-reset sequential miter against immutable raw-field reference RTL. Outputs
hierarchical/flattened inventories, AIGER with arbitrary payload initialization,
PDR logs/invariants/counterexamples under build/verification/tl_prepared_equivalence.
Next audit counterexamples or establish proved lemmas if the full query times out.
"""
from pathlib import Path
import argparse
import json
import re
import shlex
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha
from run_reference import REFERENCE,DEPENDENCIES

OUTPUTS={'o_valid':1,'o_taken':1,'o_group_done':1,'o_error':1,'o_shortfall':1,'o_control':256,'o_tags':256,'o_fields':4,'o_end':4,'o_cursor':4,'o_source_ready':1,'o_captured':1}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label',default='rtl')
    parser.add_argument('--widths',type=int,nargs='+',choices=range(8,17),default=[8,16])
    parser.add_argument('--candidate',type=Path,default=ROOT/'rtl/tl/tl_prepared_partition.v')
    parser.add_argument('--seconds',type=int,default=180)
    parser.add_argument('--prepare-only',action='store_true',help='prepare full real-state miter without running PDR')
    args=parser.parse_args()
    need(args.label.replace('_','').replace('-','').isalnum() and args.seconds>0 and len(set(args.widths))==len(args.widths),'invalid label/budget/matrix')
    stage=ROOT/'build/verification/tl_prepared_equivalence'/args.label;stage.mkdir(parents=True,exist_ok=False)
    baseline=stage/'baseline';baseline.mkdir();compiled=stage/'compiled';compiled.mkdir()
    names=[Path(n).stem for n in DEPENDENCIES]
    def isolate(text):return re.sub(r'\b('+ '|'.join(names)+r')\b',lambda m:'baseline_'+m[0],text)
    for name in DEPENDENCIES:
        source=subprocess.check_output(['git','show',REFERENCE+':rtl/tl/'+name],cwd=ROOT)
        (baseline/name).write_bytes(source);(compiled/name).write_text(isolate(source.decode()))
    reference=Path(__file__).with_name('reference.v');need(reference.is_file(),'reference module missing')
    (stage/'reference.v').write_bytes(reference.read_bytes());(compiled/'reference.v').write_text(isolate(reference.read_text()))
    (compiled/'candidate.v').write_bytes(args.candidate.read_bytes())
    current_sources=[args.candidate.resolve(),reference.resolve()]
    for name in ('tl_control_decode.v','tl_control_tenure.v'):
        p=ROOT/'rtl/tl'/name;current_sources.append(p);(compiled/('candidate_'+name)).write_bytes(p.read_bytes())
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    result=dict(complete=False,reference=REFERENCE,sources={str(p):sha(p) for p in current_sources},baseline={p.name:sha(p) for p in baseline.iterdir()},compiled={p.name:sha(p) for p in compiled.iterdir()},public_output_bits=531,reset_contract='one forced synchronous reset edge, then arbitrary external reset and inputs',initial_payload='arbitrary via write_aiger -zinit, not forced zero',signal_cuts=[],results=[])
    for width in args.widths:
        folder=stage/f'w{width}';folder.mkdir()
        inputs=dict(i_clk=1,i_rstn=1,i_source_valid=1,i_ready=1,i_done=1,i_response=1,i_auth=1,i_shared=1,i_source_control=256,i_source_tags=512,i_capacity=20*(width+1))
        declarations=','.join(f'input wire [{bits-1}:0] {name}' for name,bits in inputs.items())
        connections=','.join(f'.{name}({"checked_rstn" if name=="i_rstn" else name})' for name in inputs)
        def output_connections(bus):
            shift=0;parts=[]
            for name,bits in OUTPUTS.items():parts.append(f'.{name}({bus}[{shift}+:{bits}])');shift+=bits
            need(shift==531,'complete output miter')
            return ','.join(parts)
        miter=f'''module miter({declarations},output wire o_bad);
reg started=0;always @(posedge i_clk)started<=1'b1;
wire checked_rstn=started&&i_rstn;wire [530:0] gold_outputs,gate_outputs;
tl_prepared_reference #(.WIDTH({width})) gold({connections},{output_connections('gold_outputs')});
tl_prepared_partition #(.WIDTH({width})) gate({connections},{output_connections('gate_outputs')});
assign o_bad=|(gold_outputs^gate_outputs);
endmodule
'''
        (folder/'miter.v').write_text(miter)
        sources=' '.join('"'+str(p)+'"' for p in sorted(compiled.glob('*.v')))
        script=f'read_verilog {sources} "{folder}/miter.v"\nhierarchy -check -top miter\nproc\nwrite_json "{folder}/hierarchy.json"\nprep -top miter -flatten\ncheck -assert\nwrite_json "{folder}/structure.json"\ntechmap\nopt -full\ndffunmap\nabc -g AND\nopt_clean -purge\ncheck -assert\nwrite_json "{folder}/lowered.json"\nwrite_aiger -zinit -miter -symbols -map "{folder}/aiger.map" -ywmap "{folder}/witness_map.json" "{folder}/miter.aig"\n'
        # Tcl preserves option filenames containing spaces; this Yosys version
        # retains literal quote characters in write_aiger -map option values.
        def tcl_word(value):return '{'+value.replace('\\','\\\\').replace('{','\\{').replace('}','\\}')+'}'
        script=''.join('yosys '+' '.join(tcl_word(x) for x in shlex.split(line))+'\n' for line in script.splitlines())
        (folder/'prepare.tcl').write_text(script)
        prepared=execute(['yosys','-Q','-T','-c',str(folder/'prepare.tcl')],folder/'prepare.log',300)
        row=dict(width=width,prepare=prepared,passed=False);result['results'].append(row);dump(stage/'results.json',result)
        if prepared['exit']!=0:continue
        hierarchy=json.loads((folder/'hierarchy.json').read_text())['modules'];top=hierarchy['miter']
        for side in ('gold','gate'):
            module=hierarchy[top['cells'][side]['type']]
            found_in={n:len(p['bits']) for n,p in module['ports'].items() if p['direction']=='input'}
            found_out={n:len(p['bits']) for n,p in module['ports'].items() if p['direction']=='output'}
            need(found_in==inputs and found_out==OUTPUTS,'original interface inventory '+side)
        graph=json.loads((folder/'structure.json').read_text())['modules']['miter']
        flops=[c for c in graph['cells'].values() if c['type']=='$dff']
        need(flops and not any('latch' in c['type'].lower() for c in graph['cells'].values()),'state/latch inventory')
        need(all(c['connections']['CLK']==graph['ports']['i_clk']['bits'] and int(c['parameters']['CLK_POLARITY'],2)==1 for c in flops),'actual clock correspondence')
        row.update(state_bits=sum(len(c['connections']['Q']) for c in flops),aig_sha256=sha(folder/'miter.aig'))
        if args.prepare_only:
            row['prepare_only']=True;dump(stage/'results.json',result);continue
        command=f'read_aiger "{folder}/miter.aig"; pdr -T {args.seconds} -v -d -I "{folder}/invariant.pla"; write_cex -n "{folder}/counterexample.cex"'
        (folder/'proof_command.txt').write_text(command+'\n')
        proof=execute(['yosys-abc','-c',command],folder/'proof.log',args.seconds+30)
        log=(folder/'proof.log').read_text()
        row.update(proof=proof,passed=proof['exit']==0 and 'Property proved.' in log,log_tail=log[-800:]);dump(stage/'results.json',result)
        print(width,row['passed'],log[-400:],flush=True)
    result['complete']=len(result['results'])==len(args.widths) and all(r['passed'] for r in result['results'])
    result['sources_unchanged']=all(sha(p)==result['sources'][str(p)] for p in current_sources)
    result['complete']=result['complete'] and result['sources_unchanged'];dump(stage/'results.json',result)
    return 0 if result['complete'] or (args.prepare_only and all(r['prepare']['exit']==0 and r.get('prepare_only') for r in result['results'])) else 1


if __name__=='__main__':
    raise SystemExit(main())

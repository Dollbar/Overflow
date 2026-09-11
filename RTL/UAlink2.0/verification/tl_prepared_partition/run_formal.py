"""Run python3 verification/tl_prepared_partition/run_formal.py [--label formal]
[--widths 8 16] [--replace FILE] [--undef] [--properties ownership|boundaries|count_constants|all]. Produces exact instrumented RTL, structural
state inventory, inductive SAT logs and witnesses under build/verification/
tl_prepared_partition/LABEL. Next: full registered-reference/mapped equivalence.
Only ownership/reset/capture/holding/cursor invariants are claimed here.
"""
from pathlib import Path
import argparse
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'verification/tl_partition_mapping'))
from run_cec import dump, execute, need, sha

PROPERTIES = '''
reg f_past_valid=0;
always @(posedge i_clk)begin
 f_past_valid<=1;
 if(!f_past_valid)assume(!i_rstn);
 if(f_past_valid)begin
  if(!$past(i_rstn))begin assert(!r_owned);assert(r_cursor==0);end
  if(i_rstn&&$past(i_rstn))begin
   assert(r_owned==(($past(r_owned)&&!$past(o_group_done))||$past(o_captured)));
   if($past(o_captured))begin
    assert({r_control,r_tags,r_capacity,r_auth,r_shared,r_error,r_starts,r_application,r_counts,r_slots}==$past({i_source_control,i_source_tags,i_capacity,i_auth,i_shared,format_error,starts[7:1],application_starts,source_counts,source_slots}));
   end else begin
    assert({r_control,r_tags,r_capacity,r_auth,r_shared,r_error,r_starts,r_application,r_counts,r_slots}==$past({r_control,r_tags,r_capacity,r_auth,r_shared,r_error,r_starts,r_application,r_counts,r_slots}));
   end
   if($past(o_valid&&!i_ready))assert({o_valid,o_control,o_tags,o_fields,o_end,o_cursor}==$past({o_valid,o_control,o_tags,o_fields,o_end,o_cursor}));
   if($past(o_taken))assert(r_cursor==($past(o_group_done)?4'd0:$past(o_end)));
   else assert(r_cursor==$past(r_cursor));
  end
  assert(r_cursor<8);
  if(r_owned&&!r_error)assert(r_cursor==0||r_starts[r_cursor]);
  if(!r_owned)assert(r_cursor==0);
 end
 if(!i_rstn)assert({o_source_ready,o_captured,o_valid,o_taken,o_group_done,o_error,o_shortfall,o_control,o_tags,o_fields,o_end,o_cursor}==0);
 if(!o_valid)assert({o_control,o_tags,o_fields,o_end}==0);
end
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', default='formal')
    parser.add_argument('--widths', type=int, nargs='+', choices=range(8, 17), default=[8, 16])
    parser.add_argument('--replace', type=Path)
    parser.add_argument('--undef', action='store_true', help='diagnostic defined-input/state encoding; default is binary SAT')
    parser.add_argument('--properties', choices=('ownership','boundaries','count_constants','all'), default='all')
    args = parser.parse_args()
    need(args.label.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    stage = ROOT / 'build/verification/tl_prepared_partition' / args.label
    stage.mkdir(parents=True, exist_ok=False)
    sources = [(args.replace or ROOT / 'rtl/tl/tl_prepared_partition.v').resolve()] + [ROOT / 'rtl/tl' / n for n in ('tl_control_decode.v', 'tl_control_tenure.v')]
    for source in sources: (stage / source.name).write_bytes(source.read_bytes())
    source = sources[0].read_text(); need(source.count('endmodule') == 1, 'one top required')
    properties = PROPERTIES
    if args.properties == 'ownership':
        # A local transition proof. Complete-field boundary reachability and
        # public combinational outputs are left to the broader proof attempt.
        properties = properties.replace('if($past(o_valid&&!i_ready))assert({o_valid,o_control,o_tags,o_fields,o_end,o_cursor}==$past({o_valid,o_control,o_tags,o_fields,o_end,o_cursor}));', 'if($past(o_valid&&!i_ready))assert({r_owned,r_cursor,r_control,r_tags,r_capacity,r_auth,r_shared,r_error,r_starts,r_application,r_counts,r_slots}==$past({r_owned,r_cursor,r_control,r_tags,r_capacity,r_auth,r_shared,r_error,r_starts,r_application,r_counts,r_slots}));')
        properties = properties.replace('  assert(r_cursor<8);\n', '').replace('  if(r_owned&&!r_error)assert(r_cursor==0||r_starts[r_cursor]);\n', '')
    elif args.properties == 'boundaries':
        properties = '''
reg f_past_valid=0;
always @(posedge i_clk)begin
 f_past_valid<=1;
 if(!f_past_valid)assume(!i_rstn);
 if(f_past_valid)begin
  assert(r_cursor<8);
  if(r_owned&&!r_error)assert(r_cursor==0||r_starts[r_cursor]);
  if(!r_owned)assert(r_cursor==0);
 end
end
'''
    elif args.properties == 'count_constants':
        properties = '''
reg f_past_valid=0;
always @(posedge i_clk)begin
 f_past_valid<=1;
 if(!f_past_valid)assume(!i_rstn);
 if(f_past_valid&&r_owned)
  assert({r_counts[28],r_counts[24],r_counts[20],r_counts[16],r_counts[12],r_counts[8],r_counts[4],r_counts[0]}==0);
end
'''
    (stage / 'proof.sv').write_text(source.replace('endmodule', properties + '\nendmodule'))
    (stage / 'runner.py').write_bytes(Path(__file__).read_bytes())
    scopes={'ownership':'binary reset/capture/ownership/state holding and cursor transition','boundaries':'binary reachable cursor range and captured complete-field boundaries','count_constants':'binary owned implies all eight unused captured count LSBs zero','all':'binary reset/capture/ownership/output holding/cursor boundary invariants; not full functional or mapped equivalence'}
    result = dict(complete=False, properties=args.properties, undef_encoding=args.undef, scope=scopes[args.properties], sources={str(p): sha(p) for p in sources}, results=[])
    for width in args.widths:
        folder = stage / f'w{width}'; folder.mkdir()
        deps = ' '.join('"'+str(stage / p.name)+'"' for p in sources[1:])
        # Check the real design before adding verification history registers.
        script = f'read_verilog "{stage / sources[0].name}" {deps}\nchparam -set WIDTH {width} tl_prepared_partition\nprep -top tl_prepared_partition -flatten\ncheck -assert\nwrite_json "{folder / "structure.json"}"\n'
        (folder / 'structure.ys').write_text(script)
        structural = execute(['yosys', '-Q', '-T', '-s', str(folder / 'structure.ys')], folder / 'structure.log', 120)
        need(structural['exit'] == 0, 'structural synthesis failed')
        graph = json.loads((folder / 'structure.json').read_text())['modules']['tl_prepared_partition']
        state = [c for c in graph['cells'].values() if c['type'] == '$dff']
        need(state and not any('latch' in c['type'].lower() for c in graph['cells'].values()), 'missing state or latch')
        need(all(c['connections']['CLK'] == graph['ports']['i_clk']['bits'] and int(c['parameters']['CLK_POLARITY'], 2) == 1 for c in state), 'derived or incorrect clock')
        state_bits = sum(len(c['connections']['Q']) for c in state)
        inputs = {n:len(p['bits']) for n,p in graph['ports'].items() if p['direction']=='input'}
        outputs = {n:len(p['bits']) for n,p in graph['ports'].items() if p['direction']=='output'}
        need(sum(outputs.values()) == 531 and len(outputs) == 12, 'public outputs omitted')
        need(inputs == dict(i_clk=1,i_rstn=1,i_source_valid=1,i_ready=1,i_done=1,i_response=1,i_auth=1,i_shared=1,i_source_control=256,i_source_tags=512,i_capacity=20*(width+1)), 'public inputs omitted')
        script = f'read_verilog -formal -sv "{stage / "proof.sv"}" {deps}\nchparam -set WIDTH {width} tl_prepared_partition\nprep -top tl_prepared_partition -flatten\ncheck -assert\n'
        encoding = '-set-def-inputs -set-init-def' if args.undef else ''
        script += f'sat -seq 2 -tempinduct -maxsteps 4 -set-assumes {encoding} -prove-asserts -verify -dump_json "{folder / "witness.json"}"\n'
        (folder / 'proof.ys').write_text(script)
        proof = execute(['yosys', '-Q', '-T', '-s', str(folder / 'proof.ys')], folder / 'proof.log', 240)
        log = (folder / 'proof.log').read_text()
        row = dict(width=width, structural=structural, state_bits=state_bits, input_bits=sum(inputs.values()), output_bits=sum(outputs.values()), proof=proof, passed=proof['exit']==0 and 'Induction step proven: SUCCESS!' in log)
        result['results'].append(row); dump(stage / 'results.json', result)
        print(width, row['passed'], proof, flush=True)
    result['complete'] = all(r['passed'] for r in result['results']) and all(sha(p)==result['sources'][str(p)] for p in sources)
    dump(stage / 'results.json', result)
    return 0 if result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

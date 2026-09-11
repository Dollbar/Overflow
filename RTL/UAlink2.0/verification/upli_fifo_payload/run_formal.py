"""Run python3 verification/upli_fifo_payload/run_formal.py --kd28-root PATH
--label NEW [--depths 1 2 3 5] [--widths 8 32 512] [--raw 0 1]
[--fault head|reservation]. Prove the actual FIFO with the authorized parameterized
synchronous SRAM model against an independent shift queue. Outputs source/graph
snapshots, exact observations, properties, induction logs and counterexamples under
build/verification/upli_fifo_payload/NEW. Next audit payload invariants and connect
them to physical bank mapping and TL assembly; this is not macro timing signoff.
"""
from pathlib import Path
import argparse
import copy
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'verification/tl_partition_mapping'))
from run_cec import dump, execute, need, sha


def composition(depth, width, raw):
    cw = depth.bit_length()
    return f'''module fifo_memory(
 input wire i_clk,i_rstn,i_write_valid,i_read_ready,
 input wire [{width-1}:0] i_write_data,
 output wire o_write_ready,o_read_valid,
 output wire [{width-1}:0] o_read_data,
 output wire [{cw-1}:0] o_count);
 wire wcs,rcs;
 (* keep = 1 *) wire [{cw-1}:0] wa,ra;
 wire [{width-1}:0] wd,rd;
 upli_receive_fifo #(.C_DEPTH({depth}),.C_DATA_WIDTH({width}),.C_ZERO_INVALID({1-raw})) Fifo_Inst(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_write_valid(i_write_valid),.i_write_data(i_write_data),
 .o_write_ready(o_write_ready),.i_read_ready(i_read_ready),.o_read_valid(o_read_valid),
 .o_read_data(o_read_data),.o_count(o_count),.o_sram_write_cs(wcs),.o_sram_write_addr(wa),
 .o_sram_write_data(wd),.o_sram_read_cs(rcs),.o_sram_read_addr(ra),.i_sram_read_data(rd));
 kd28_sram_sdp_model #(.DATA_WIDTH({width}),.DEPTH({depth}),.ADDR_WIDTH({cw}),.MASK_WIDTH({width//8})) SRAM_Inst(
 .write_clk_i(i_clk),.write_cs_i(wcs),.write_addr_i(wa),.write_data_i(wd),
 .write_mask_i({width//8}'h{(1 << (width//8))-1:x}),.read_clk_i(i_clk),.read_cs_i(rcs),.read_addr_i(ra),.read_data_o(rd));
endmodule
'''


def observations(depth):
    fields = {f'f_{short}': 'Fifo_Inst.' + name for short, name in (
        ('cached', 'cnt_cached'), ('pending', 'reg_pending'), ('unread', 'cnt_unread'),
        ('head', 'reg_head'), ('tail', 'reg_tail'))}
    fields.update(f_wcs='wcs', f_rcs='rcs', f_wa='wa', f_ra='ra', f_wd='wd', f_rd='rd')
    fields.update({f'f_mem_{i}': f'SRAM_Inst.memory[{i}]' for i in range(depth)})
    return fields


def observe(original, depth):
    result = copy.deepcopy(original)
    top = result['modules']['fifo_memory']
    for name, net in observations(depth).items():
        need(name not in top['ports'] and net in top['netnames'], 'missing/colliding observation ' + net)
        top['ports'][name] = dict(direction='output', bits=top['netnames'][net]['bits'])
    return result


def audit_observation(original, observed, depth):
    restored = copy.deepcopy(observed)
    top = restored['modules']['fifo_memory']
    for name, net in observations(depth).items():
        need(top['ports'].pop(name) == dict(direction='output', bits=original['modules']['fifo_memory']['netnames'][net]['bits']),
             'changed observation ' + name)
    need(restored == original, 'changed actual cell/state/net/port outside observations')
    clock = top['ports']['i_clk']['bits']
    states = [c for c in top['cells'].values() if c['type'] == '$dff']
    need(states and all(c['connections']['CLK'] == clock and int(c['parameters']['CLK_POLARITY'], 2) == 1 for c in states),
         'actual clock changed')
    need(not any('latch' in c['type'].lower() or c['type'].startswith('$mem') for c in top['cells'].values()),
         'unexpanded memory or latch')
    return dict(state_bits=sum(len(c['connections']['Q']) for c in states), added_outputs=len(observations(depth)),
                removed_cells=0, free_internal_inputs=0)


def properties(ports, depth, width, raw):
    decl = lambda n, p: f'[{len(p["bits"])-1}:0] {n}'
    inputs = [n for n, p in ports.items() if p['direction'] == 'input']
    text = 'module properties(\n' + ',\n'.join('input wire ' + decl(n, ports[n]) for n in inputs) + '\n);\n'
    text += '\n'.join('wire ' + decl(n, p) + ';' for n, p in ports.items() if p['direction'] == 'output') + '\n'
    text += 'fifo_memory dut(' + ','.join(f'.{n}({n})' for n in ports) + ');\n'
    cw = depth.bit_length()
    text += f'''reg started=0;
reg [{cw}:0] ref_count;
reg [{width-1}:0] reference[0:{depth-1}];
wire [{width-1}:0] actual_memory[0:{depth-1}];
wire push=i_rstn&&i_write_valid&&(ref_count<{depth});
wire pop=i_rstn&&i_read_ready&&o_read_valid;
reg [2:0] wait_age;
'''
    for i in range(depth):
        text += f'assign actual_memory[{i}]=f_mem_{i};\n'
    text += f'''always @(posedge i_clk)begin
 started<=1;
 if(!started)assume(!i_rstn);
 if(!i_rstn)begin ref_count<=0;wait_age<=0;end
 else begin
  ref_count<=ref_count+push-pop;
  if(ref_count==0||o_read_valid)wait_age<=0;
  else wait_age<=wait_age+1;
 end
 if(started)begin
  assert(ref_count<={depth});
  assert(o_count==ref_count);
  assert(o_write_ready==(i_rstn&&(ref_count<{depth})));
  assert(f_wcs==push);
  assert(f_wd==i_write_data);
  assert(f_wa<{depth}&&f_ra<{depth});
  assert(f_cached<=2);
  assert({{1'b0,f_cached}}+f_pending<=3'd2);
  assert(f_unread<={depth});
  assert(ref_count=={{1'b0,f_unread}}+{{1'b0,f_cached}}+f_pending);
  assert(f_wa==((f_ra+32'd0+f_unread)%32'd{depth}));
  assert(!(f_wcs&&f_rcs&&(f_wa==f_ra)));
  assert(!o_read_valid||(ref_count!=0));
  if(o_read_valid)begin assert(o_read_data==reference[0]);assert(f_head==reference[0]);end
  if(f_pending)assert(f_rd==reference[f_cached]);
  assert(wait_age<=2);
  if(wait_age==2)assert(o_read_valid);
'''
    if not raw:
        text += f"  if(!o_read_valid)assert(o_read_data=={width}'d0);\n"
    else:
        text += '  assert(o_read_data==f_head);\n'
    if depth > 1:
        text += '  if(f_cached==2)assert(f_tail==reference[1]);\n'
    for i in range(depth):
        text += f'  if(f_unread>{i})assert(actual_memory[(f_ra+32\'d{i})%32\'d{depth}]==reference[f_cached+32\'d0+f_pending+32\'d{i}]);\n'
    text += ' end\nend\n'
    for i in range(depth):
        text += f'''always @(posedge i_clk)begin
 if(i_rstn)begin
  if(push&&((ref_count-pop)=={i}))reference[{i}]<=i_write_data;
'''
        if i < depth - 1:
            text += f'  else if(pop)reference[{i}]<=reference[{i+1}];\n'
        text += ' end\nend\n'
    return text + 'endmodule\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kd28-root', type=Path, required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--widths', type=int, nargs='+', choices=(8, 32, 512), default=[8])
    parser.add_argument('--depths', type=int, nargs='+', choices=(1, 2, 3, 5), default=[1, 2, 3, 5])
    parser.add_argument('--raw', type=int, nargs='+', choices=(0, 1), default=[0])
    parser.add_argument('--fault', choices=('head', 'reservation'))
    args = parser.parse_args()
    need(args.label.replace('_', '').replace('-', '').isalnum(), 'invalid label')
    need(all(len(x) == len(set(x)) for x in (args.widths, args.depths, args.raw)), 'duplicate configurations')
    stage = ROOT / 'build/verification/upli_fifo_payload' / args.label
    stage.mkdir(parents=True, exist_ok=False)
    fifo = ROOT / 'rtl/upli/upli_receive_fifo.v'
    model = args.kd28_root.resolve() / 'Library/models/kd28/sram/rtl/kd28_sram_sdp_model.v'
    need(model.is_file(), 'missing authorized SRAM model')
    source = fifo.read_text()
    mutation = None
    if args.fault:
        old, new = (('reg_head <= i_sram_read_data;', 'reg_head <= ~i_sram_read_data;') if args.fault == 'head' else
                    ("(reserved < 3'd2)", "(survivors < 2'd2)"))
        need(source.count(old) == 1, 'actual fault site changed')
        source = source.replace(old, new)
        mutation = dict(old=old, new=new)
    (stage / fifo.name).write_text(source)
    (stage / model.name).write_bytes(model.read_bytes())
    (stage / 'runner.py').write_bytes(Path(__file__).read_bytes())
    result = dict(complete=False, fault=args.fault, mutation=mutation,
                  sources={str(p): sha(p) for p in (fifo, model)}, results=[],
                  assumptions=['initial synchronous reset'], actual_sram_behavior=True,
                  physical_bank_mapping=False, macro_signoff=False, full_goal_complete=False)
    # Non-power-of-two memory mapping leaves invalid-address mux leaves undriven.
    # Preserve these as explicit undef, never zero; reachable address bounds are
    # assertions in the proof, not environmental assumptions.
    for width in args.widths:
        for depth in args.depths:
            for raw in args.raw:
                folder = stage / f'w{width}_d{depth}_raw{raw}'
                folder.mkdir()
                (folder / 'composition.sv').write_text(composition(depth, width, raw))
                script = f'read_verilog "{stage/fifo.name}" "{stage/model.name}"\nread_verilog -sv "{folder}/composition.sv"\nprep -top fifo_memory -flatten\nmemory_map\nopt_expr -undriven\nopt_clean\ncheck -assert\nwrite_json "{folder}/original.json"\n'
                (folder / 'prepare.ys').write_text(script)
                row = dict(width=width, depth=depth, raw=raw, passed=False,
                           prepare=execute(['yosys', '-Q', '-T', '-s', str(folder / 'prepare.ys')], folder / 'prepare.log', 120))
                result['results'].append(row)
                dump(stage / 'results.json', result)
                need(row['prepare']['exit'] == 0, 'actual composition failed to elaborate')
                original = json.loads((folder / 'original.json').read_text())
                observed = observe(original, depth)
                row['boundary'] = audit_observation(original, observed, depth)
                dump(folder / 'observed.json', observed)
                (folder / 'properties.sv').write_text(properties(observed['modules']['fifo_memory']['ports'], depth, width, raw))
                script = f'read_json "{folder}/observed.json"\nread_verilog -formal -sv "{folder}/properties.sv"\nprep -top properties -flatten\nmemory_map\nopt_expr -undriven\nopt_clean\ncheck -assert\nwrite_json "{folder}/proof.json"\nsat -seq 2 -tempinduct -maxsteps 12 -set-assumes -prove-asserts -verify -show-inputs -show-outputs -dump_json "{folder}/witness.json"\n'
                (folder / 'proof.ys').write_text(script)
                row['proof'] = execute(['yosys', '-Q', '-T', '-s', str(folder / 'proof.ys')], folder / 'proof.log', 180)
                log = (folder / 'proof.log').read_text()
                row['induction_proven'] = row['proof']['exit'] == 0 and 'Induction step proven: SUCCESS!' in log
                row['counterexample'] = row['proof']['exit'] == 1 and 'model found for base case: FAIL!' in log
                row['passed'] = row['counterexample'] if args.fault else row['induction_proven']
                dump(stage / 'results.json', result)
                print(row, flush=True)
    result['complete'] = all(row['passed'] for row in result['results'])
    dump(stage / 'results.json', result)
    return 0 if result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

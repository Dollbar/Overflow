"""Run: python3 verification/tl_tx_prepared/run_formal.py --kd28-root PATH
--label ownership --widths 8 16 --depths 1 2 3 [--fault tags|enqueue|reset].
Outputs source snapshots, actual flattened graphs, memory abstraction inventory,
inductive SAT logs and witnesses under build/verification/tl_tx_prepared/LABEL.
Only SRAM output values are arbitrary; no internal control/state is replaced.
Next: full payload correspondence, actual mapped equivalence and process STA.
"""
from pathlib import Path
import argparse
import copy
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'verification/tl_partition_mapping'))
from run_cec import dump, execute, need, sha


def properties(ports, depth):
    inputs = [(n, p) for n, p in ports.items() if p['direction'] == 'input']
    outputs = [(n, p) for n, p in ports.items() if p['direction'] == 'output']
    decl = lambda n, p: f'[{len(p["bits"])-1}:0] {n}'
    text = 'module properties(\n' + ',\n'.join('input wire '+decl(n,p) for n,p in inputs) + '\n);\n'
    text += '\n'.join('wire '+decl(n,p)+';' for n,p in outputs) + '\n'
    text += 'tl_tx_prepared dut(\n'+',\n'.join(f'.{n}({n})' for n in ports)+'\n);\n'
    text += '''reg started=0;
always @(posedge i_clk)begin
 started<=1;
 if(!started)assume(!i_rstn);
 assert(o_source_captured==(i_source_valid&o_source_ready));
 assert(o_source_tags_taken==(i_auth?o_source_captured:2'b00));
 if(i_auth&&!i_source_tags_valid[0])assert(!o_source_ready[0]);
 if(i_auth&&!i_source_tags_valid[1])assert(!o_source_ready[1]);
 if(!i_rstn)assert({o_source_ready,o_source_captured,o_source_tags_taken,o_partition_taken,o_group_queued}==0);
 if(started&&f_hold==3'd1)begin
  assert(f_hold_valid);
  assert((f_hold_class?f_cached_1:f_cached_0)!=0);
 end
end
'''
    cw = len(ports['o_header_count']['bits'])//2
    for lane in (0,1):
        text += f'''reg [2:0] groups_{lane};
reg [{cw+1}:0] queued_{lane};
always @(posedge i_clk)begin
 if(!i_rstn)begin groups_{lane}<=0;queued_{lane}<=0;end
 else begin
  groups_{lane}<=groups_{lane}+{{2'b00,o_source_captured[{lane}]}}-{{2'b00,o_group_queued[{lane}]}};
  queued_{lane}<=queued_{lane}+o_partition_taken[{lane}]-o_header_taken[{lane}];
 end
 if(started)begin
  assert(groups_{lane}<=1);
  assert(groups_{lane}==f_owned_{lane});
  assert(queued_{lane}<={depth});
  assert(queued_{lane}==o_header_count[{lane*cw}+:{cw}]);
  assert(f_cached_{lane}<=2);
  assert({{1'b0,f_cached_{lane}}}+f_pending_{lane}<=2);
  assert(f_unread_{lane}<={depth});
  assert({{2'b00,o_header_count[{lane*cw}+:{cw}]}}=={{2'b00,f_unread_{lane}}}+f_cached_{lane}+f_pending_{lane});
  assert(!o_group_queued[{lane}]||f_owned_{lane});
  assert(!o_source_captured[{lane}]||!f_owned_{lane}||o_group_queued[{lane}]);
  assert(o_partition_taken[{lane}]==f_write_{lane});
  assert(o_header_taken[{lane}]==f_consume_{lane});
  if(!$past(i_rstn))begin assert(!f_owned_{lane});assert(o_header_count[{lane*cw}+:{cw}]==0);end
 end
end
'''
    return text+'endmodule\n'


def observe_and_abstract(raw):
    graph = copy.deepcopy(raw)
    top = graph['modules']['tl_tx_prepared']
    obs = {}
    for lane in (0,1):
        prefix = f'Buffered_Inst.gen_queues[{lane}].Header_Inst.Fifo_Inst.'
        names = {'owned': f'gen_prepare[{lane}].Prepare_Inst.r_owned',
                 'unread': prefix+'cnt_unread', 'cached': prefix+'cnt_cached',
                 'pending': prefix+'reg_pending', 'write': prefix+'flag_write',
                 'consume': prefix+'flag_consume'}
        for short, original in names.items():
            bits = top['netnames'][original]['bits']
            name = f'f_{short}_{lane}'
            need(name not in top['ports'], 'observation port collision')
            top['ports'][name] = dict(direction='output', bits=bits)
            obs[name] = dict(original=original, bits=bits)
    for name, original in {'f_hold':'Buffered_Inst.Channels_Inst.Packer_Inst.r_hold',
                           'f_hold_valid':'Buffered_Inst.Channels_Inst.r_hold_valid',
                           'f_hold_class':'Buffered_Inst.Channels_Inst.r_hold_class'}.items():
        bits=top['netnames'][original]['bits']
        top['ports'][name]=dict(direction='output',bits=bits)
        obs[name]=dict(original=original,bits=bits)
    macros = {n:c for n,c in top['cells'].items() if c['type'].startswith('KD28_SRAM')}
    need(len(macros)==64, 'unexpected macro denominator')
    clock = top['ports']['i_clk']['bits']
    memories = []
    for index, (name,cell) in enumerate(macros.items()):
        need(cell['connections']['RCLK']==clock and cell['connections']['WCLK']==clock, 'macro clock mismatch')
        outputs = {n:b for n,b in cell['connections'].items() if cell['port_directions'][n]=='output'}
        need(len(outputs)==1, 'unexpected macro output interface')
        for port,bits in outputs.items():
            top['ports'][f'f_memory_{index}'] = dict(direction='input', bits=bits)
        memories.append(dict(name=name, cell=cell, input_port=f'f_memory_{index}'))
        del top['cells'][name]
    ff = [c for c in top['cells'].values() if c['type']=='$dff']
    need(ff and all(c['connections']['CLK']==clock and int(c['parameters']['CLK_POLARITY'],2)==1 for c in ff), 'actual FF clock mismatch')
    need(not any('latch' in c['type'].lower() for c in top['cells'].values()), 'latch in actual design')
    return graph, dict(observations=obs, memories=memories, state_bits=sum(len(c['connections']['Q']) for c in ff), internal_control_cuts=0)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--kd28-root',type=Path,required=True)
    p.add_argument('--label',required=True)
    p.add_argument('--widths',type=int,nargs='+',choices=range(8,17),default=[8,16])
    p.add_argument('--depths',type=int,nargs='+',choices=(1,2,3),default=[1,2,3])
    p.add_argument('--fault',choices=('tags','enqueue','reset'))
    a=p.parse_args()
    need(a.label.replace('_','').replace('-','').isalnum(),'invalid label')
    need(len(set(a.widths))==len(a.widths) and len(set(a.depths))==len(a.depths),'duplicate configuration')
    stage=ROOT/'build/verification/tl_tx_prepared'/a.label
    stage.mkdir(parents=True,exist_ok=False)
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    src=sorted((ROOT/'rtl/tl').glob('*.v'))+[ROOT/'rtl/upli/upli_receive_fifo.v',ROOT/'rtl/upli/upli_receive_storage.v']
    external=a.kd28_root.resolve()/'Library/models/kd28'
    deps=[external/'sram/rtl/kd28_sram_blackboxes.v',external/'fifo/rtl/kd28_fifo_sdp_storage_map.v']
    report=dict(complete=False,fault=a.fault,sources={str(x):sha(x) for x in src+deps},results=[],
                assumptions=['initial synchronous reset'],internal_control_cuts=0,
                memory_scope='arbitrary SRAM output value each step; no memory payload integrity claim',
                full_payload_formal=False,full_top_sta=False,full_goal_complete=False)
    snapshots=[]
    for path in src:
        dst=stage/path.name;dst.write_bytes(path.read_bytes());snapshots.append(dst)
    if a.fault:
        dst=stage/'tl_tx_prepared.v';source=dst.read_text()
        changes={'tags':('assign tags_ready=!i_auth||i_source_tags_valid[lane];',"assign tags_ready=1'b1;"),
                 'enqueue':('.i_ready(partition_ready[lane])',".i_ready(1'b1)"),
                 'reset':('.i_rstn(i_rstn),.i_source_valid','.i_rstn(i_rstn||i_source_valid[lane]),.i_source_valid')}
        old,new=changes[a.fault];need(source.count(old)==1,'mutation anchor mismatch')
        dst.write_text(source.replace(old,new));report['mutation']=dict(old=old,new=new,sha256=sha(dst))
    dump(stage/'results.json',report)
    for width in a.widths:
        for depth in a.depths:
            folder=stage/f'w{width}_d{depth}';folder.mkdir()
            script='read_verilog '+' '.join('"'+str(x)+'"' for x in snapshots+deps)+f'\nchparam -set WIDTH {width} -set HEADER_DEPTH {depth} tl_tx_prepared\nprep -top tl_tx_prepared -flatten\ncheck -assert\nwrite_json "{folder}/original.json"\n'
            (folder/'prepare.ys').write_text(script)
            row=dict(width=width,depth=depth,prepare=execute(['yosys','-Q','-T','-s',str(folder/'prepare.ys')],folder/'prepare.log',120),passed=False)
            report['results'].append(row);dump(stage/'results.json',report)
            need(row['prepare']['exit']==0,'actual top elaboration failed')
            graph,inventory=observe_and_abstract(json.loads((folder/'original.json').read_text()))
            dump(folder/'observed.json',graph);dump(folder/'inventory.json',inventory)
            (folder/'properties.sv').write_text(properties(graph['modules']['tl_tx_prepared']['ports'],depth))
            signals='i_rstn,i_auth,i_source_valid,i_source_tags_valid,o_source_ready,o_source_captured,o_source_tags_taken,o_partition_taken,o_group_queued,o_header_count,o_header_taken,f_write_0,f_write_1,f_consume_0,f_consume_1,f_owned_0,f_owned_1'
            script=f'read_json "{folder}/observed.json"\nread_verilog -formal -sv "{folder}/properties.sv"\nprep -top properties -flatten\nopt_clean\ncheck -assert\nwrite_json "{folder}/proof.json"\nsat -seq 2 -tempinduct -maxsteps 6 -set-assumes -prove-asserts -verify -show {signals} -dump_json "{folder}/witness.json"\n'
            (folder/'proof.ys').write_text(script)
            row['proof']=execute(['yosys','-Q','-T','-s',str(folder/'proof.ys')],folder/'proof.log',240)
            log=(folder/'proof.log').read_text()
            row['passed']=row['proof']['exit']==0 and 'Induction step proven: SUCCESS!' in log
            row['counterexample']=row['proof']['exit']==1 and 'model found for base case: FAIL!' in log and (folder/'witness.json').is_file()
            row['state_bits']=inventory['state_bits'];dump(stage/'results.json',report)
            print(row,flush=True)
    report['complete']=len(report['results'])==len(a.widths)*len(a.depths) and all(r['passed'] for r in report['results'])
    need(all(sha(Path(n))==v for n,v in report['sources'].items()),'source changed while proving')
    dump(stage/'results.json',report)
    return 0 if report['complete'] else 1


if __name__=='__main__':raise SystemExit(main())

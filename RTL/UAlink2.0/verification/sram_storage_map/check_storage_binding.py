"""Run python3 verification/sram_storage_map/check_storage_binding.py
--kd28-root PATH --label NEW [--widths 256 512 600] [--depths 1 2 3 5].
Elaborate actual production storage and functional fixed SRAM cells; verify exact
wrapper parameters and every FIFO/mapper/model connection. Write graphs, logs
and evidence.json under build/verification/sram_storage_map/NEW. Next combine
the structural binding with matching FIFO and mapper behavior proofs; this check
alone is not a new full-payload or physical macro proof.
"""
import argparse
import copy
import json
from pathlib import Path
from run_formal import ROOT,geometry,dump,execute,need,sha


def params(module,expected):
    values=module['parameter_default_values']
    for name,value in expected.items():
        need(name in values and int(values[name],2)==value,'wrong elaborated parameter '+name)


def inspect_binding(graph,width,depth,raw):
    modules=graph['modules'];top=modules['binding'];g=geometry(width,depth)
    need(set(top['cells'])=={'dut'},'extra top binding logic')
    dut=top['cells']['dut'];need(dut['type'].endswith('\\upli_receive_storage'),'not actual production wrapper')
    storage=modules[dut['type']]
    expected=dict(C_DEPTH=depth,C_DATA_WIDTH=width,C_COUNT_WIDTH=g['address'],C_ZERO_INVALID=1-raw)
    params(storage,expected)
    need(set(storage['cells'])=={'Fifo_Inst','Storage_Inst'},'unexpected wrapper logic')
    fifo=storage['cells']['Fifo_Inst'];mapper=storage['cells']['Storage_Inst']
    need(fifo['type'].endswith('\\upli_receive_fifo') and mapper['type'].endswith('\\kd28_fifo_sdp_storage_map'),'different actual storage components')
    params(modules[fifo['type']],expected)
    params(modules[mapper['type']],dict(DATA_WIDTH=width,DEPTH=max(2,depth),ADDR_WIDTH=g['address']))
    sizes={n:1 for n in ('i_clk','i_rstn','i_write_valid','i_read_ready','o_write_ready','o_read_valid')}
    sizes.update(i_write_data=width,o_read_data=width,o_count=g['address'])
    need(set(top['ports'])==set(storage['ports'])==set(sizes),'storage public interface changed')
    for name,size in sizes.items():
        port=storage['ports'][name]
        need(len(port['bits'])==size and port['direction']==('input' if name.startswith('i_') else 'output'),'public port width/direction changed')
        need(dut['connections'][name]==top['ports'][name]['bits'],'top binding gate/bypass')
        need(fifo['connections'][name]==port['bits'],'FIFO public binding gate/bypass')
    pairs={'write_clk_i':'i_clk','write_cs_i':'o_sram_write_cs','write_addr_i':'o_sram_write_addr',
           'write_data_i':'o_sram_write_data','read_clk_i':'i_clk','read_cs_i':'o_sram_read_cs',
           'read_addr_i':'o_sram_read_addr','read_data_o':'i_sram_read_data'}
    need(set(mapper['connections'])==set(pairs),'mapper pin set changed')
    for pin,other in pairs.items():
        need(mapper['connections'][pin]==fifo['connections'][other],'FIFO/mapper connection changed: '+pin)
    mapped=modules[mapper['type']]
    macros=[c for c in mapped['cells'].values() if c['type'].startswith('KD28_SRAM_')]
    need(len(macros)==g['banks']*g['tiles'],'macro instance count differs from contract')
    types={c['type'] for c in macros};need(types=={f"KD28_SRAM_SDP_{g['rows']}X{g['bits']}"},'wrong functional macro class')
    for kind in types:
        fixed=modules[kind];need(set(fixed['cells'])=={'u_model'},'fixed cell is not a pure behavior binding')
        cell=fixed['cells']['u_model'];need(cell['type'].endswith('\\kd28_sram_sdp_model'),'different functional SRAM model')
        model=modules[cell['type']]
        params(model,dict(DATA_WIDTH=g['bits'],DEPTH=g['rows'],ADDR_WIDTH=g['macro_address'],MASK_WIDTH=g['bits']//8))
        signals=dict(write_clk_i='WCLK',write_cs_i='WCS',write_addr_i='WA',write_data_i='D',write_mask_i='WM',
                     read_clk_i='RCLK',read_cs_i='RCS',read_addr_i='RA',read_data_o='Q')
        need(set(cell['connections'])==set(signals),'functional model port set differs')
        for pin,other in signals.items():
            need(cell['connections'][pin]==fixed['ports'][other]['bits'],'functional macro/model binding changed: '+pin)
        need(not fixed.get('attributes',{}).get('blackbox'),'functional macro remained blackbox')
    return dict(width=width,depth=depth,raw=raw,macro_count=len(macros),macro_class=next(iter(types)),
                exact_fifo_mapper_binding=True,exact_functional_model_binding=True,full_payload_proof=False)


def wrapper(width,depth,raw):
    aw=geometry(width,depth)['address']
    return f'''module binding(input i_clk,i_rstn,i_write_valid,i_read_ready,
input [{width-1}:0] i_write_data,output o_write_ready,o_read_valid,
output [{width-1}:0] o_read_data,output [{aw-1}:0] o_count);
upli_receive_storage #(.C_DEPTH({depth}),.C_DATA_WIDTH({width}),.C_COUNT_WIDTH({aw}),.C_ZERO_INVALID({1-raw})) dut(.*);
endmodule
'''


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True);p.add_argument('--label',required=True)
    p.add_argument('--widths',type=int,nargs='+',default=[256,512,600]);p.add_argument('--depths',type=int,nargs='+',default=[1,2,3,5])
    a=p.parse_args();need(a.label.replace('_','').replace('-','').isalnum(),'invalid label')
    stage=ROOT/'build/verification/sram_storage_map'/a.label;stage.mkdir(parents=True,exist_ok=False)
    dep=a.kd28_root.resolve()/'Library/models/kd28'
    files=[ROOT/'rtl/upli/upli_receive_fifo.v',ROOT/'rtl/upli/upli_receive_storage.v',dep/'fifo/rtl/kd28_fifo_sdp_storage_map.v']
    files += [dep/'sram/rtl'/n for n in ('kd28_sram_cells.v','kd28_sram_sp_model.v','kd28_sram_sdp_model.v','kd28_sram_tdp_model.v')]
    sources={str(f):sha(f) for f in files}
    for f in files:(stage/f.name).write_bytes(f.read_bytes())
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    result=dict(complete=False,sources=sources,results=[],scope='exact production FIFO/mapper and fixed functional SRAM wrapper binding',full_goal_complete=False)
    for width in a.widths:
        for depth in a.depths:
            for raw in (0,1):
                folder=stage/f'w{width}_d{depth}_raw{raw}';folder.mkdir();(folder/'wrapper.sv').write_text(wrapper(width,depth,raw))
                script='read_verilog '+' '.join('"'+str(stage/f.name)+'"' for f in files)+f'\nread_verilog -sv "{folder}/wrapper.sv"\nhierarchy -check -top binding\nproc\ncheck -assert\nwrite_json "{folder}/binding.json"\n'
                (folder/'prepare.ys').write_text(script);run=execute(['yosys','-Q','-T','-s',str(folder/'prepare.ys')],folder/'prepare.log',120)
                need(run['exit']==0,'actual functional binding elaboration failed')
                row=inspect_binding(json.loads((folder/'binding.json').read_text()),width,depth,raw)
                row.update(elaboration=run,graph_sha256=sha(folder/'binding.json'));result['results'].append(row);dump(stage/'evidence.json',result)
    result['complete']=True;dump(stage/'evidence.json',result);print('Actual production storage bindings:',len(result['results']))


if __name__=='__main__':
    main()

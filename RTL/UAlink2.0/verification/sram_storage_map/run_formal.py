"""Run python3 verification/sram_storage_map/run_formal.py --kd28-root PATH
--label NEW --widths 32 512 --depths 3 2049 [--fault data|mask|bank].
Prove the actual fixed SRAM mapper at its macro pin boundary. Outputs immutable
sources, original/cut graphs, inventories, properties and SAT logs under
build/verification/sram_storage_map/NEW. Next combine with actual SRAM behavior
and the proved FIFO payload contract; this is not physical macro signoff.
"""
import argparse
import copy
import json
import re
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'verification/tl_partition_mapping'))
from run_cec import dump,execute,need,sha


def geometry(width,depth):
    need(width>=8 and width%8==0 and 1<=depth<=65535,'unsupported logical geometry')
    mapped=max(2,depth)
    rows,bits=next(((r,b) for r,b in ((256,32),(512,64),(1024,128),(2048,256)) if mapped<=r),(2048,256))
    return dict(rows=rows,bits=bits,tiles=(width+bits-1)//bits,banks=(mapped+rows-1)//rows,
                address=depth.bit_length(),macro_address=rows.bit_length()-1,mapped_depth=mapped)


def wrapper(width,depth):
    g=geometry(width,depth);aw=g['address']
    return f'''module mapped_storage(
input wire i_clk,i_write_cs,i_read_cs,
input wire [{aw-1}:0] i_write_addr,i_read_addr,
input wire [{width-1}:0] i_write_data,
output wire [{width-1}:0] o_read_data);
kd28_fifo_sdp_storage_map #(.DATA_WIDTH({width}),.DEPTH({g['mapped_depth']}),.ADDR_WIDTH({aw})) actual(
.write_clk_i(i_clk),.write_cs_i(i_write_cs),.write_addr_i(i_write_addr),.write_data_i(i_write_data),
.read_clk_i(i_clk),.read_cs_i(i_read_cs),.read_addr_i(i_read_addr),.read_data_o(o_read_data));
endmodule
'''


def cut_macros(original,width,depth):
    g=geometry(width,depth);cut=copy.deepcopy(original);top=cut['modules']['mapped_storage']
    inventory=[];seen=set();qbits=set()
    for name,cell in list(top['cells'].items()):
        if not cell['type'].startswith('KD28_SRAM_'):
            continue
        match=re.search(r'gen_depth_bank\[(\d+)\]\.gen_width_lane\[(\d+)\]',name)
        need(match is not None,'unidentified actual macro '+name)
        bank,tile=map(int,match.groups());key=(bank,tile)
        need(key not in seen and bank<g['banks'] and tile<g['tiles'],'extra/duplicate macro geometry')
        seen.add(key);expected=f"KD28_SRAM_SDP_{g['rows']}X{g['bits']}"
        need(cell['type']==expected,'wrong fixed macro class')
        pins={'WCLK':1,'WCS':1,'WA':g['macro_address'],'D':g['bits'],'WM':g['bits']//8,
              'RCLK':1,'RCS':1,'RA':g['macro_address'],'Q':g['bits']}
        need(set(cell['connections'])==set(pins),'macro pin set changed')
        prefix=f'm{bank}_{tile}_'
        for pin,size in pins.items():
            bits=cell['connections'][pin]
            need(len(bits)==size,'macro pin width changed')
            port=prefix+pin;need(port not in top['ports'],'colliding macro observation')
            top['ports'][port]=dict(direction='input' if pin=='Q' else 'output',bits=bits)
            if pin=='Q':
                need(all(isinstance(b,int) and b not in qbits for b in bits),'aliased/free-constant macro Q')
                qbits.update(bits)
            if pin in ('WCLK','RCLK'):
                need(bits==top['ports']['i_clk']['bits'],'macro clock is not the actual shared clock')
        inventory.append(dict(name=name,bank=bank,tile=tile,type=expected,prefix=prefix,pins=pins))
        del top['cells'][name]
    need(seen=={(b,t) for b in range(g['banks']) for t in range(g['tiles'])},'missing fixed macro')
    inventory.sort(key=lambda r:(r['bank'],r['tile']))
    return cut,inventory


def audit_cut(original,cut,inventory):
    restored=copy.deepcopy(cut);top=restored['modules']['mapped_storage'];gold=original['modules']['mapped_storage']
    for entry in inventory:
        cell=gold['cells'][entry['name']]
        for pin in entry['pins']:
            need(top['ports'].pop(entry['prefix']+pin)==dict(direction='input' if pin=='Q' else 'output',bits=cell['connections'][pin]),'changed macro pin observation')
        need(entry['name'] not in top['cells'],'macro was not cut exactly once')
        top['cells'][entry['name']]=cell
    need(restored==original,'nonmacro graph/state/port changed at the boundary')
    need(not any('latch' in c['type'].lower() for c in gold['cells'].values()),'unexpected latch')
    for cell in gold['cells'].values():
        if cell['type'].startswith('$dff'):
            need(cell['connections']['CLK']==gold['ports']['i_clk']['bits'] and int(cell['parameters']['CLK_POLARITY'],2)==1,'mapper state clock changed')


def properties(ports,width,depth,inventory,bank_reference=False):
    g=geometry(width,depth)
    decl=lambda n,p:f"[{len(p['bits'])-1}:0] {n}"
    inputs=[n for n,p in ports.items() if p['direction']=='input']
    code='module properties(\n'+',\n'.join('input wire '+decl(n,ports[n]) for n in inputs)+'\n);\n'
    code+='\n'.join('wire '+decl(n,p)+';' for n,p in ports.items() if p['direction']=='output')+'\n'
    code+='mapped_storage dut('+','.join(f'.{n}({n})' for n in ports)+');\n'
    physical=g['tiles']*g['bits'];padding=physical-width
    code+=f"wire [{physical-1}:0] padded={{{padding}'d0,i_write_data}};\n" if padding else f'wire [{physical-1}:0] padded=i_write_data;\n'
    if bank_reference:
        bank_bits=max(1,(g['banks']-1).bit_length())
        code+=f"reg seen=0;reg [{bank_bits-1}:0] last_bank;\nalways @(posedge i_clk)if(i_read_cs)begin seen<=i_read_addr<{depth};last_bank<=i_read_addr/32'd{g['rows']};end\n"
    else:
        code+=f"reg seen=0;reg [{g['address']-1}:0] last_read;\nalways @(posedge i_clk)if(i_read_cs)begin seen<=i_read_addr<{depth};last_read<=i_read_addr;end\n"
    code+=f"wire [{g['banks']*width-1}:0] logical_bank_data;\n"
    for bank in range(g['banks']):
        bundle=','.join(f'm{bank}_{tile}_Q' for tile in reversed(range(g['tiles'])))
        code+=f'wire [{physical-1}:0] bank{bank}={{{bundle}}};\nassign logical_bank_data[{bank*width} +: {width}]=bank{bank}[{width-1}:0];\n'
    code+='always @* begin\n'
    for entry in inventory:
        n=entry['prefix'];bank=entry['bank'];tile=entry['tile']
        code+=f''' assert({n}WCLK==i_clk&&{n}RCLK==i_clk);
 assert({n}WCS==(i_write_cs&&((i_write_addr/32'd{g['rows']})=={bank})));
 assert({n}RCS==(i_read_cs&&((i_read_addr/32'd{g['rows']})=={bank})));
 assert({n}WA==(i_write_addr%32'd{g['rows']}));
 assert({n}RA==(i_read_addr%32'd{g['rows']}));
 assert({n}D==padded[{tile*g['bits']} +: {g['bits']}]);
 assert({n}WM=={g['bits']//8}'h{(1<<(g['bits']//8))-1:x});
'''
    if bank_reference:
        for bank in range(g['banks']):
            code+=f" if(seen&&last_bank=={bank})assert(o_read_data==bank{bank}[{width-1}:0]);\n"
        code+='end\nendmodule\n'
    else:
        code+=f" if(seen)assert(o_read_data==logical_bank_data[(last_read/32'd{g['rows']})*{width} +: {width}]);\nend\nendmodule\n"
    return code


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kd28-root',type=Path,required=True)
    p.add_argument('--label',required=True);p.add_argument('--widths',type=int,nargs='+',default=[32,512])
    p.add_argument('--depths',type=int,nargs='+',default=[3,2049]);p.add_argument('--fault',choices=('data','mask','bank'))
    p.add_argument('--bank-reference',action='store_true',help='capture only the independent quotient needed for read-bank selection')
    p.add_argument('--bit-lower',action='store_true',help='lower the retained proof graph to bit-level gates before SAT')
    a=p.parse_args();need(a.label.replace('_','').replace('-','').isalnum(),'invalid label')
    need(len(a.widths)==len(set(a.widths)) and len(a.depths)==len(set(a.depths)),'duplicate configurations')
    stage=ROOT/'build/verification/sram_storage_map'/a.label;stage.mkdir(parents=True,exist_ok=False)
    dep=a.kd28_root.resolve()/'Library/models/kd28'
    mapper=dep/'fifo/rtl/kd28_fifo_sdp_storage_map.v';boxes=dep/'sram/rtl/kd28_sram_blackboxes.v'
    source=mapper.read_text();mutation=None
    if a.fault:
        old,new={'data':('.D(write_data_padded[lane_index*MACRO_WIDTH +: MACRO_WIDTH])','.D(~write_data_padded[lane_index*MACRO_WIDTH +: MACRO_WIDTH])'),
                 'mask':('.WM({MACRO_MASK_WIDTH{1\'b1}})', '.WM({MACRO_MASK_WIDTH{1\'b0}})'),
                 'bank':('bank_read_data[(read_bank_q*PHYSICAL_WIDTH)', 'bank_read_data[(read_bank_select*PHYSICAL_WIDTH)')}[a.fault]
        need(source.count(old)==(1 if a.fault=='bank' else 4),'actual mapper fault site changed')
        source=source.replace(old,new);mutation=dict(old=old,new=new)
    (stage/mapper.name).write_text(source);(stage/boxes.name).write_bytes(boxes.read_bytes())
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    result=dict(complete=False,results=[],fault=a.fault,mutation=mutation,sources={str(f):sha(f) for f in (mapper,boxes)},
                assumptions=[],macro_read_boundary='independent arbitrary Q words; actual macro behavior is a separate contract',
                physical_signoff=False,full_goal_complete=False)
    if a.bank_reference: result['reference_profile']='captured_bank'
    if a.bit_lower: result['bit_lower']=True
    for width in a.widths:
        for depth in a.depths:
            folder=stage/f'w{width}_d{depth}';folder.mkdir();(folder/'wrapper.v').write_text(wrapper(width,depth))
            prepare=f'read_verilog "{stage/mapper.name}" "{stage/boxes.name}" "{folder}/wrapper.v"\nprep -top mapped_storage -flatten\ncheck -assert\nwrite_json "{folder}/original.json"\n'
            (folder/'prepare.ys').write_text(prepare)
            row=dict(width=width,depth=depth,passed=False,prepare=execute(['yosys','-Q','-T','-s',str(folder/'prepare.ys')],folder/'prepare.log',120))
            result['results'].append(row);dump(stage/'results.json',result);need(row['prepare']['exit']==0,'actual mapper elaboration failed')
            original=json.loads((folder/'original.json').read_text());cut,inventory=cut_macros(original,width,depth);audit_cut(original,cut,inventory)
            dump(folder/'cut.json',cut);dump(folder/'inventory.json',inventory)
            (folder/'properties.sv').write_text(properties(cut['modules']['mapped_storage']['ports'],width,depth,inventory,a.bank_reference))
            query='-seq 4' if a.fault else '-seq 2 -tempinduct -maxsteps 8'
            optimization='wreduce\nopt -full -keepdc' if a.bank_reference else 'opt -keepdc'
            if a.bit_lower: optimization+='\ntechmap\nopt -full -keepdc'
            script=f'read_json "{folder}/cut.json"\nread_verilog -formal -sv "{folder}/properties.sv"\nprep -top properties -flatten\n{optimization}\ncheck -assert\nwrite_json "{folder}/proof.json"\nsat {query} -prove-asserts -verify -show-inputs -dump_json "{folder}/witness.json"\n'
            (folder/'proof.ys').write_text(script);row['proof']=execute(['yosys','-Q','-T','-s',str(folder/'proof.ys')],folder/'proof.log',120)
            log=(folder/'proof.log').read_text();row['macros']=len(inventory);row['properties']=len(inventory)*7+(geometry(width,depth)['banks'] if a.bank_reference else 1)
            row['induction_proven']=row['proof']['exit']==0 and 'Induction step proven: SUCCESS!' in log
            row['counterexample']=row['proof']['exit']==1 and 'SAT proof finished - model found: FAIL!' in log
            row['passed']=row['counterexample'] if a.fault else row['induction_proven']
            dump(stage/'results.json',result);print(row,flush=True)
    result['complete']=all(r['passed'] for r in result['results']);dump(stage/'results.json',result)
    return 0 if result['complete'] else 1


if __name__=='__main__':
    raise SystemExit(main())

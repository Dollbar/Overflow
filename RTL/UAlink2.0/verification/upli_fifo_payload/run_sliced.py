"""Run python3 verification/upli_fifo_payload/run_sliced.py --source payload_full
--width 512 --depth 3 --raw 0 --chunk-width 64 --label NEW. Prove every payload
bit in independent slices of the same actual FIFO/SRAM graph; retain all control
assertions in each query and add no assumptions or internal inputs. Outputs
per-slice properties, scripts, graphs/logs and results.json. Next independently
audit complete bit coverage and combine both output modes and all depths.
"""
import argparse
import json
from pathlib import Path

from run_formal import ROOT, dump, execute, need, sha
from check_formal import check_graph, check_properties


def coverage(width,chunk):
    need(width>0 and chunk>0,'invalid payload partition size')
    return [(lo,min(chunk,width-lo)) for lo in range(0,width,chunk)]


def slice_properties(source,width,lo,size,depth):
    need(0<=lo<width and 0<size<=width-lo,'invalid payload bit range')
    result=source
    replacements={f'reg [{width-1}:0] reference':f'reg [{size-1}:0] reference',
                  f'wire [{width-1}:0] actual_memory':f'wire [{size-1}:0] actual_memory',
                  'o_read_data==reference[0]':f'o_read_data[{lo} +: {size}]==reference[0]',
                  'f_head==reference[0]':f'f_head[{lo} +: {size}]==reference[0]',
                  'f_rd==reference[f_cached]':f'f_rd[{lo} +: {size}]==reference[f_cached]'}
    if depth>1:
        replacements['f_tail==reference[1]']=f'f_tail[{lo} +: {size}]==reference[1]'
    for i in range(depth):
        replacements[f'actual_memory[{i}]=f_mem_{i};']=f'actual_memory[{i}]=f_mem_{i}[{lo} +: {size}];'
        replacements[f'reference[{i}]<=i_write_data;']=f'reference[{i}]<=i_write_data[{lo} +: {size}];'
    for old,new in replacements.items():
        need(result.count(old)==1,'payload obligation changed: '+old)
        result=result.replace(old,new)
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',required=True);p.add_argument('--label',required=True)
    p.add_argument('--width',type=int,default=512);p.add_argument('--depth',type=int,required=True)
    p.add_argument('--raw',type=int,choices=(0,1),required=True);p.add_argument('--chunk-width',type=int,default=64)
    a=p.parse_args()
    need(all(n.replace('_','').replace('-','').isalnum() for n in (a.source,a.label)),'invalid label')
    base=ROOT/'build/verification/upli_fifo_payload';stage=base/a.label;stage.mkdir(exist_ok=False)
    parent=base/a.source;source=parent/f'w{a.width}_d{a.depth}_raw{a.raw}'
    metadata=json.loads((parent/'results.json').read_text())
    need(metadata['fault'] is None,'healthy source required')
    for name,digest in metadata['sources'].items():
        need(sha(Path(name))==digest and sha(parent/Path(name).name)==digest,'actual source/model changed')
    original=json.loads((source/'original.json').read_text());observed=json.loads((source/'observed.json').read_text())
    boundary=check_graph(original,observed,a.depth,a.width)
    props=(source/'properties.sv').read_text();count=check_properties(props,a.depth,a.width,a.raw)
    parts=coverage(a.width,a.chunk_width)
    result=dict(complete=False,width=a.width,depth=a.depth,raw=a.raw,parts=parts,results=[],boundary=boundary,
                source_hashes={str(source/n):sha(source/n) for n in ('original.json','observed.json','composition.sv','properties.sv')},
                actual_sources=metadata['sources'],assumptions=['initial synchronous reset'],
                full_actual_composition=True,free_internal_inputs=0,full_goal_complete=False)
    (stage/'runner.py').write_bytes(Path(__file__).read_bytes())
    for lo,size in parts:
        folder=stage/f'bits_{lo}_{lo+size-1}';folder.mkdir()
        (folder/'properties.sv').write_text(slice_properties(props,a.width,lo,size,a.depth))
        script=f'read_json "{source}/observed.json"\nread_verilog -formal -sv "{folder}/properties.sv"\nprep -top properties -flatten\nmemory_map\nopt_expr -undriven\nopt_clean\ncheck -assert\nwrite_json "{folder}/proof.json"\nsat -seq 2 -tempinduct -maxsteps 12 -set-assumes -prove-asserts -verify\n'
        (folder/'proof.ys').write_text(script)
        run=execute(['yosys','-Q','-T','-s',str(folder/'proof.ys')],folder/'proof.log',180)
        log=(folder/'proof.log').read_text()
        row=dict(low_bit=lo,bits=size,properties=count,run=run,passed=run['exit']==0 and 'Induction step proven: SUCCESS!' in log)
        result['results'].append(row);dump(stage/'results.json',result);print(row,flush=True)
    result['complete']=len(result['results'])==len(parts) and all(r['passed'] for r in result['results'])
    dump(stage/'results.json',result)
    return 0 if result['complete'] else 1


if __name__=='__main__':
    raise SystemExit(main())

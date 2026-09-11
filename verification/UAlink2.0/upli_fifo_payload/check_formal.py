"""Run python3 verification/upli_fifo_payload/check_formal.py --label payload_full
[--slice-labels RUN ...] [--output PATH]. Audit exact source, unchanged observed graphs, proof commands,
critical reference obligations and actual induction logs. Write evidence.json.
Next combine this SRAM-contract proof with the fixed bank mapper and TL payload.
"""
import argparse
import copy
import json
import re
from pathlib import Path

from run_formal import ROOT, composition, properties, dump, need, sha


def check_graph(original, observed, depth, width):
    need(set(original['modules']) == {'fifo_memory'}, 'unexpected original hierarchy')
    restored = copy.deepcopy(observed)
    top = restored['modules']['fifo_memory']
    gold = original['modules']['fifo_memory']
    names = dict(f_cached='Fifo_Inst.cnt_cached', f_pending='Fifo_Inst.reg_pending',
                 f_unread='Fifo_Inst.cnt_unread', f_head='Fifo_Inst.reg_head',
                 f_tail='Fifo_Inst.reg_tail', f_wcs='wcs', f_rcs='rcs', f_wa='wa',
                 f_ra='ra', f_wd='wd', f_rd='rd')
    names.update({f'f_mem_{i}': f'SRAM_Inst.memory[{i}]' for i in range(depth)})
    for port, net in names.items():
        need(top['ports'].pop(port) == {'direction': 'output', 'bits': gold['netnames'][net]['bits']}, 'wrong observation ' + port)
    need(restored == original, 'graph changed beyond output observations')
    need({n for n,p in gold['ports'].items() if p['direction']=='input'} ==
         {'i_clk','i_rstn','i_write_valid','i_write_data','i_read_ready'}, 'extra actual input')
    states = [c for c in gold['cells'].values() if c['type'] == '$dff']
    need(all(c['connections']['CLK'] == gold['ports']['i_clk']['bits'] and
             int(c['parameters']['CLK_POLARITY'],2)==1 for c in states), 'wrong actual clock')
    need(not any('latch' in c['type'].lower() or c['type'].startswith(('$mem','$assume','$any')) for c in gold['cells'].values()), 'unexpected abstract state/assumptions')
    bits = sum(len(c['connections']['Q']) for c in states)
    need(bits == width*(depth+3)+4*depth.bit_length()+3, 'actual state inventory incomplete')
    memory_bits = [bit for i in range(depth) for bit in gold['netnames'][f'SRAM_Inst.memory[{i}]']['bits']]
    need(len(memory_bits)==width*depth and len(set(memory_bits))==len(memory_bits) and all(isinstance(b,int) for b in memory_bits), 'missing or aliased actual SRAM state')
    need(not any('init' in n.get('attributes',{}) for n in gold['netnames'].values()), 'actual SRAM/FIFO state initialized by proof')
    return dict(state_bits=bits, actual_memory_bits=len(memory_bits), observation_ports=len(names), free_internal_inputs=0)


def check_properties(source, depth, width, raw):
    # These obligations are reviewed independently from the runner's string
    # generator. Structural checks supplement, not replace, that semantic review.
    text = re.sub(r'\s+', '', source)
    clauses = [
        'regstarted=0;', 'started<=1;', 'if(!started)assume(!i_rstn);',
        f'wirepush=i_rstn&&i_write_valid&&(ref_count<{depth});',
        'wirepop=i_rstn&&i_read_ready&&o_read_valid;',
        'if(!i_rstn)beginref_count<=0;wait_age<=0;end',
        'ref_count<=ref_count+push-pop;',
        'if(ref_count==0||o_read_valid)wait_age<=0;elsewait_age<=wait_age+1;',
        f'assert(ref_count<={depth});', 'assert(o_count==ref_count);',
        f'assert(o_write_ready==(i_rstn&&(ref_count<{depth})));',
        'assert(f_wcs==push);','assert(f_wd==i_write_data);',
        f'assert(f_wa<{depth}&&f_ra<{depth});', 'assert(f_cached<=2);',
        "assert({1'b0,f_cached}+f_pending<=3'd2);",f'assert(f_unread<={depth});',
        "assert(ref_count=={1'b0,f_unread}+{1'b0,f_cached}+f_pending);",
        f"assert(f_wa==((f_ra+32'd0+f_unread)%32'd{depth}));",
        'assert(!(f_wcs&&f_rcs&&(f_wa==f_ra)));',
        'assert(!o_read_valid||(ref_count!=0));',
        'if(o_read_valid)beginassert(o_read_data==reference[0]);assert(f_head==reference[0]);end',
        'if(f_pending)assert(f_rd==reference[f_cached]);',
        'assert(wait_age<=2);if(wait_age==2)assert(o_read_valid);',
        'assert(o_read_data==f_head);' if raw else f"if(!o_read_valid)assert(o_read_data=={width}'d0);",
    ]
    if depth>1:
        clauses.append('if(f_cached==2)assert(f_tail==reference[1]);')
    for i in range(depth):
        clauses += [f'assignactual_memory[{i}]=f_mem_{i};',
                    f"if(f_unread>{i})assert(actual_memory[(f_ra+32'd{i})%32'd{depth}]==reference[f_cached+32'd0+f_pending+32'd{i}]);",
                    f'if(push&&((ref_count-pop)=={i}))reference[{i}]<=i_write_data;']
        if i<depth-1:
            clauses.append(f'elseif(pop)reference[{i}]<=reference[{i+1}];')
    need(all(text.count(c)==1 for c in clauses), 'missing/changed reference or payload obligation')
    count=19+depth+(depth>1)
    need(text.count('assert(')==count and text.count('assume(')==1 and text.count('always@(posedgei_clk)')==depth+1,
         'unexpected assertion/assumption/process inventory')
    need('initial' not in text and text.count('if(started)begin')==1, 'unexpected initialization or proof gate')
    return count


def check_slice_coverage(parts,width):
    bits=[]
    for low,size in parts:
        need(isinstance(low,int) and isinstance(size,int) and 0<=low<width and 0<size<=width-low,'invalid slice bounds')
        bits.extend(range(low,low+size))
    need(bits==list(range(width)),'payload bit gap, overlap or reordering')


def check_slices(stage,source,width,depth,raw,actual_sources):
    from run_sliced import slice_properties
    result=json.loads((stage/'results.json').read_text())
    need(result['complete'] and (result['width'],result['depth'],result['raw'])==(width,depth,raw),'incomplete/wrong slice configuration')
    need(result['actual_sources']==actual_sources and result['assumptions']==['initial synchronous reset'] and
         result['free_internal_inputs']==0 and result['full_actual_composition'],'slice boundary changed')
    need(set(result['source_hashes'])=={str(source/n) for n in ('original.json','observed.json','composition.sv','properties.sv')},'slices use a different original composition')
    for name,digest in result['source_hashes'].items():
        need(sha(Path(name))==digest,'slice source changed')
    check_slice_coverage(result['parts'],width)
    need(len(result['results'])==len(result['parts']),'missing slice result')
    files=[stage/'results.json',stage/'runner.py'];lengths=[]
    full=(source/'properties.sv').read_text()
    for (low,size),row in zip(result['parts'],result['results']):
        need((row['low_bit'],row['bits'])==(low,size) and row['passed'] and row['run']['exit']==0,'slice failed/wrong bit range')
        folder=stage/f'bits_{low}_{low+size-1}'
        need((folder/'properties.sv').read_text()==slice_properties(full,width,low,size,depth),'sliced payload obligations changed')
        script=f'read_json "{source}/observed.json"\nread_verilog -formal -sv "{folder}/properties.sv"\nprep -top properties -flatten\nmemory_map\nopt_expr -undriven\nopt_clean\ncheck -assert\nwrite_json "{folder}/proof.json"\nsat -seq 2 -tempinduct -maxsteps 12 -set-assumes -prove-asserts -verify\n'
        need((folder/'proof.ys').read_text()==script,'slice proof command weakened')
        graph=json.loads((folder/'proof.json').read_text())['modules']['properties']
        need(sum(c['type']=='$assume' for c in graph['cells'].values())==1 and
             sum(c['type']=='$assert' for c in graph['cells'].values())==19+depth+(depth>1),'slice elaborated obligations changed')
        log=(folder/'proof.log').read_text();steps=re.findall(r'Base case for induction length (\d+) proven\.',log)
        need(steps and log.count('Induction step proven: SUCCESS!')==1 and 'ERROR:' not in log,'slice induction incomplete')
        lengths.append(int(steps[-1]));files.extend(p for p in folder.iterdir() if p.is_file())
    return dict(method='complete_payload_slices',slices=len(lengths),induction_length=max(lengths)),files


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label',required=True)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--slice-labels',nargs='*',default=[])
    args=parser.parse_args()
    need(args.label.replace('_','').replace('-','').isalnum(),'invalid label')
    stage=ROOT/'build/verification/upli_fifo_payload'/args.label
    result=json.loads((stage/'results.json').read_text())
    need(result['fault'] is None,'healthy matrix required')
    need(result['assumptions']==['initial synchronous reset'] and result['actual_sram_behavior'] and not result['physical_bank_mapping'],'wrong scope')
    for name,digest in result['sources'].items():
        path=Path(name)
        need(sha(path)==digest and sha(stage/path.name)==digest,'changed actual source/model')
    need(sha(stage/'runner.py')==sha(Path(__file__).with_name('run_formal.py')),'runner changed since proof')
    sliced={}
    for label in args.slice_labels:
        need(label.replace('_','').replace('-','').isalnum(),'invalid slice label')
        path=stage.parent/label;meta=json.loads((path/'results.json').read_text())
        key=(meta['width'],meta['depth'],meta['raw']);need(key not in sliced,'duplicate slice configuration');sliced[key]=path
    seen=set();used=set();rows=[];files=[stage/'results.json',stage/'runner.py']
    for row in result['results']:
        w,d,raw=row['width'],row['depth'],row['raw'];key=(w,d,raw)
        need(key not in seen,'duplicate configuration');seen.add(key)
        folder=stage/f'w{w}_d{d}_raw{raw}'
        need(row['prepare']['exit']==0 and 'proof' in row,'actual elaboration/proof not completed')
        need((folder/'composition.sv').read_text()==composition(d,w,raw),'actual FIFO/SRAM wiring changed')
        prepare=f'read_verilog "{stage}/upli_receive_fifo.v" "{stage}/kd28_sram_sdp_model.v"\nread_verilog -sv "{folder}/composition.sv"\nprep -top fifo_memory -flatten\nmemory_map\nopt_expr -undriven\nopt_clean\ncheck -assert\nwrite_json "{folder}/original.json"\n'
        need((folder/'prepare.ys').read_text()==prepare,'actual source elaboration changed')
        original=json.loads((folder/'original.json').read_text());observed=json.loads((folder/'observed.json').read_text())
        inventory=check_graph(original,observed,d,w)
        need((folder/'properties.sv').read_text()==properties(observed['modules']['fifo_memory']['ports'],d,w,raw),'full reviewed property program changed')
        count=check_properties((folder/'properties.sv').read_text(),d,w,raw)
        proof=json.loads((folder/'proof.json').read_text())['modules']['properties']
        need(sum(c['type']=='$assume' for c in proof['cells'].values())==1 and
             sum(c['type']=='$assert' for c in proof['cells'].values())==count,'elaborated obligations changed')
        command=f'read_json "{folder}/observed.json"\nread_verilog -formal -sv "{folder}/properties.sv"\nprep -top properties -flatten\nmemory_map\nopt_expr -undriven\nopt_clean\ncheck -assert\nwrite_json "{folder}/proof.json"\nsat -seq 2 -tempinduct -maxsteps 12 -set-assumes -prove-asserts -verify -show-inputs -show-outputs -dump_json "{folder}/witness.json"\n'
        need((folder/'proof.ys').read_text()==command,'proof command changed')
        log=(folder/'proof.log').read_text()
        lengths=re.findall(r'Base case for induction length (\d+) proven\.',log)
        if row['proof']['exit']==0 and row['induction_proven'] and row['passed']:
            need(lengths and log.count('Induction step proven: SUCCESS!')==1 and 'ERROR:' not in log,'base/induction log incomplete')
            method=dict(method='whole_word_induction',induction_length=int(lengths[-1]))
        else:
            need(key in sliced,'unproved payload configuration')
            method,additional=check_slices(sliced[key],folder,w,d,raw,result['sources'])
            used.add(key);files+=additional
        rows.append(dict(width=w,depth=d,raw=raw,properties=count,**method,**inventory))
        files += [p for p in folder.iterdir() if p.is_file() and p.suffix in ('.json','.ys','.sv','.log')]
    need(seen=={(w,d,r) for w in (8,32,512) for d in (1,2,3,5) for r in (0,1)},'full requested 24-configuration matrix incomplete')
    need(used==set(sliced),'unused slice evidence')
    output=args.output or stage/'evidence.json'
    dump(output,dict(complete=True,configurations=len(rows),results=rows,hashes={str(p):sha(p) for p in files},
                     assumptions=result['assumptions'],scope='actual FIFO payload under synchronous parameterized SRAM behavior',
                     physical_bank_mapping=False,full_tl_payload=False,macro_signoff=False,full_goal_complete=False))
    print('FIFO payload evidence audited:',len(rows),'configurations')


if __name__=='__main__':
    main()

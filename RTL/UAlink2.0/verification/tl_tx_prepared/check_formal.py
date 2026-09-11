"""Run: python3 verification/tl_tx_prepared/check_formal.py [--prefix ownership] [--output FILE].
Audit the actual ownership_final matrix and three ownership_*_final fault runs.
Outputs source-bound ownership_evidence.json; preliminary attempts stay separate.
Next: full payload formal correspondence and actual combined-top process STA.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'build/verification/tl_tx_prepared'


def require(ok, message):
    if not ok:raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit_transform(original, observed):
    """Compare every cell/port/module, allowing exactly the documented SRAM cut."""
    expected=copy.deepcopy(original)
    top=expected['modules']['tl_tx_prepared']
    memory_names=[n for n,c in top['cells'].items() if c['type'].startswith('KD28_SRAM')]
    require(len(memory_names)==64,'actual macro count changed')
    for index,name in enumerate(memory_names):
        cell=top['cells'].pop(name)
        require(all(cell['connections'][p]==top['ports']['i_clk']['bits'] for p in ('RCLK','WCLK')),'macro clock changed')
        outputs=[b for p,b in cell['connections'].items() if cell['port_directions'][p]=='output']
        require(len(outputs)==1 and all(isinstance(b,int) for b in outputs[0]),'bad memory output')
        top['ports'][f'f_memory_{index}']=dict(direction='input',bits=outputs[0])
    state_map={'f_hold':'Buffered_Inst.Channels_Inst.Packer_Inst.r_hold',
               'f_hold_class':'Buffered_Inst.Channels_Inst.r_hold_class',
               'f_hold_valid':'Buffered_Inst.Channels_Inst.r_hold_valid'}
    for lane in (0,1):
        state_map[f'f_owned_{lane}']=f'gen_prepare[{lane}].Prepare_Inst.r_owned'
        for short,net in (('unread','cnt_unread'),('cached','cnt_cached'),('pending','reg_pending'),('write','flag_write'),('consume','flag_consume')):
            state_map[f'f_{short}_{lane}']=f'Buffered_Inst.gen_queues[{lane}].Header_Inst.Fifo_Inst.{net}'
    for name,net in state_map.items():
        top['ports'][name]=dict(direction='output',bits=top['netnames'][net]['bits'])
    require(expected==observed,'transformation changed control/state/ports outside the exact memory abstraction')
    state=[c for c in top['cells'].values() if c['type']=='$dff']
    require(state and all(c['connections']['CLK']==top['ports']['i_clk']['bits'] and int(c['parameters']['CLK_POLARITY'],2)==1 for c in state),'actual FF clock mismatch')
    require(not any('latch' in c['type'].lower() for c in top['cells'].values()),'latch')
    return dict(macros=64,observations=len(state_map),state_bits=sum(len(c['connections']['Q']) for c in state),internal_control_cuts=0)


def audit_properties(source, depth, graph):
    compact=re.sub(r'\s+','',source)
    require(source.count('assume(')==1 and 'if(!started)assume(!i_rstn);' in compact,'extra environment assumptions')
    required=['regstarted=0;', 'started<=1;',
              'assert(o_source_captured==(i_source_valid&o_source_ready));',
              "assert(o_source_tags_taken==(i_auth?o_source_captured:2'b00));",
              "if(started&&f_hold==3'd1)beginassert(f_hold_valid);assert((f_hold_class?f_cached_1:f_cached_0)!=0);end",
              'if(!i_rstn)assert({o_source_ready,o_source_captured,o_source_tags_taken,o_partition_taken,o_group_queued}==0);']
    cw=depth.bit_length()
    for lane in (0,1):
        count=f'o_header_count[{lane*cw}+:{cw}]'
        required.extend([
            f'if(i_auth&&!i_source_tags_valid[{lane}])assert(!o_source_ready[{lane}]);',
            f'if(!i_rstn)begingroups_{lane}<=0;queued_{lane}<=0;end',
            f"groups_{lane}<=groups_{lane}+{{2'b00,o_source_captured[{lane}]}}-{{2'b00,o_group_queued[{lane}]}};",
            f'queued_{lane}<=queued_{lane}+o_partition_taken[{lane}]-o_header_taken[{lane}];',
            f'assert(groups_{lane}<=1);', f'assert(groups_{lane}==f_owned_{lane});',
            f'assert(queued_{lane}<={depth});',f'assert(queued_{lane}=={count});',
            f'assert(f_cached_{lane}<=2);',f"assert({{1'b0,f_cached_{lane}}}+f_pending_{lane}<=2);",
            f'assert(f_unread_{lane}<={depth});',
            f"assert({{2'b00,{count}}}=={{2'b00,f_unread_{lane}}}+f_cached_{lane}+f_pending_{lane});",
            f'assert(!o_group_queued[{lane}]||f_owned_{lane});',
            f'assert(!o_source_captured[{lane}]||!f_owned_{lane}||o_group_queued[{lane}]);',
            f'assert(o_partition_taken[{lane}]==f_write_{lane});',
            f'assert(o_header_taken[{lane}]==f_consume_{lane});',
            f'if(!$past(i_rstn))beginassert(!f_owned_{lane});assert({count}==0);end'])
    require(all(x in compact for x in required),'missing or changed theorem')
    cells=list(graph['modules']['properties']['cells'].values())
    require(sum(c['type']=='$assert' for c in cells)==35,'compiled assertion denominator changed')
    require(sum(c['type']=='$assume' for c in cells)==1,'compiled assumption denominator changed')
    require(not any(c['type'].startswith('KD28') for c in cells),'unabstracted unknown memory')


def wave_values(signal):
    values=[];data=iter(signal.get('data',[]));last=None
    for c in signal['wave']:
        if c=='.':pass
        elif c in '01':last=int(c)
        elif c in '=23456789':
            word=next(data) if 'data' in signal else ''
            last=int(word,2) if word and all(b in '01' for b in word) else None
        elif c in 'xz':last=None
        else:raise ValueError('unknown witness wave encoding')
        values.append(last)
    return values


def fault_witness(path, fault):
    signals={s['name']:wave_values(s) for s in json.loads(path.read_text())['signal']}
    names=('i_rstn','i_auth','i_source_tags_valid','o_source_ready','o_source_captured','o_partition_taken','o_group_queued','f_write_0','f_write_1','f_owned_0','f_owned_1')
    require(all(n in signals for n in names),'missing actual counterexample signals')
    violations=[]
    for t in range(1,min(len(signals[n]) for n in names)):
        v={n:signals[n][t] for n in names}
        if any(x is None for x in v.values()):continue
        if fault=='tags':bad=v['i_auth'] and bool(v['o_source_ready']&(~v['i_source_tags_valid']&3))
        elif fault=='enqueue':bad=v['o_partition_taken']!=(v['f_write_0']|(v['f_write_1']<<1))
        else:
            bad=not v['i_rstn'] and bool(v['o_source_ready']|v['o_source_captured']|v['o_partition_taken']|v['o_group_queued'])
            if t>1 and signals['i_rstn'][t-1]==0:bad=bad or bool(v['f_owned_0']|v['f_owned_1'])
        if bad:violations.append(dict(step=t,signals=v))
    require(violations,'witness does not demonstrate the named actual wiring failure')
    return violations


def audit_stage(label, fault):
    stage=BASE/label;report=json.loads((stage/'results.json').read_text())
    require(report['fault']==fault and report['assumptions']==['initial synchronous reset'] and report['internal_control_cuts']==0,'proof scope mismatch')
    require((stage/'runner.py').read_bytes()==(ROOT/'verification/tl_tx_prepared/run_formal.py').read_bytes(),'runner source drift')
    for name,digest in report['sources'].items():
        path=Path(name);require(sha(path)==digest,'current source mismatch: '+name)
        if path.is_relative_to(ROOT/'rtl'):
            actual=(stage/path.name).read_text();expected=path.read_text()
            if fault and path.name=='tl_tx_prepared.v':
                old,new=report['mutation']['old'],report['mutation']['new']
                require(expected.count(old)==1,'fault not on actual unique RTL wiring')
                expected=expected.replace(old,new)
            require(actual==expected,'source snapshot mismatch')
    configs={(r['width'],r['depth']) for r in report['results']}
    require(configs==({(w,d) for w in range(8,17) for d in (1,2,3)} if fault is None else {(8,1),(16,1)}),'incomplete parameter matrix')
    require(len(report['results'])==len(configs),'duplicate configuration')
    results=[]
    for row in report['results']:
        folder=stage/f'w{row["width"]}_d{row["depth"]}'
        require(row['prepare']['exit']==0,'failed elaboration')
        original=json.loads((folder/'original.json').read_text());observed=json.loads((folder/'observed.json').read_text())
        boundary=audit_transform(original,observed)
        audit_properties((folder/'properties.sv').read_text(),row['depth'],json.loads((folder/'proof.json').read_text()))
        script=(folder/'proof.ys').read_text();log=(folder/'proof.log').read_text()
        require('sat -seq 2 -tempinduct -maxsteps 6 -set-assumes -prove-asserts -verify' in script and script.count('sat ')==1,'changed proof command')
        item=dict(width=row['width'],depth=row['depth'],boundary=boundary,proof_log_sha256=sha(folder/'proof.log'))
        if fault:
            require(row['proof']['exit']==1 and row['counterexample'] and not row['passed'] and 'model found for base case: FAIL!' in log,'no actual reset-reachable counterexample')
            item['violations']=fault_witness(folder/'witness.json',fault)
        else:
            require(row['proof']['exit']==0 and row['passed'] and 'Induction step proven: SUCCESS!' in log and 'ERROR:' not in log,'no completed unbounded proof')
            lengths=re.findall(r'\*\* Trying induction with length (\d+) \*\*',log)
            require(lengths and f'Base case for induction length {lengths[-1]} proven.' in log,'missing induction base')
            item['induction_length']=int(lengths[-1])
        results.append(item)
    require(report['complete']==(fault is None),'stage completion flag mismatch')
    return results


def audit_cover(width, impossible=False, prefix='ownership'):
    parent=prefix+'_final'
    stage=BASE/(prefix+'_cover_red' if impossible else f'{prefix}_cover_w{width}')
    report=json.loads((stage/'results.json').read_text())
    require(report['complete'] and report['parent']==parent and report['impossible']==impossible,'cover scope mismatch')
    require((stage/'runner.py').read_bytes()==(ROOT/'verification/tl_tx_prepared/run_formal_cover.py').read_bytes(),'cover runner drift')
    require(len(report['results'])==1,'unexpected cover matrix')
    row=report['results'][0];folder=stage/f'w{width}'
    require(row['width']==width and row['run']['exit']==0,'cover tool failure')
    source=BASE/parent/f'w{width}_d1/proof.json'
    require(row['proof_graph']==str(source) and row['proof_graph_sha256']==sha(source),'cover did not use actual proven graph')
    script=(folder/'cover.ys').read_text();log=(folder/'cover.log').read_text()
    require('sat -seq 6 -set-assumes -set i_auth 1 -set i_taken 0' in script,'changed cover environment')
    if impossible:
        require('-set-at 3 i_source_tags_valid 0' in script and row['excluded'] and not row['witness'] and 'SAT solving finished - no model found.' in log,'missing impossible capture exclusion')
        return dict(width=width,missing_tags_capture_excluded=True)
    require(row['witness'] and not row['excluded'] and 'SAT solving finished - model found:' in log,'no actual reachability witness')
    signals={s['name']:wave_values(s) for s in json.loads((folder/'witness.json').read_text())['signal']}
    expected={1:dict(i_rstn=0),3:dict(o_source_captured=3,o_group_queued=3),
              4:dict(i_rstn=1,f_owned_0=1,f_owned_1=1,o_header_count=3,o_partition_taken=0),
              5:dict(i_rstn=0),6:dict(i_rstn=1,f_owned_0=0,f_owned_1=0,o_header_count=0)}
    for t,row in expected.items():
        require(all(signals[n][t]==v for n,v in row.items()),'reachability trace does not meet exact ownership scenario')
    require(signals['i_auth'][1:7]==[1]*6 and signals['i_taken'][1:7]==[0]*6,'cover environment trace changed')
    return dict(width=width,both_lane_replacement_step=3,full_queue_stall_step=4,occupied_reset_step=5,cleared_step=6,witness_sha256=sha(folder/'witness.json'))


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--prefix',default='ownership');p.add_argument('--output',type=Path);a=p.parse_args()
    require(a.prefix.replace('_','').replace('-','').isalnum(),'invalid label prefix')
    output=a.output or BASE/(a.prefix+'_evidence.json')
    result=dict(complete=False,rtl_sha256=sha(ROOT/'rtl/tl/tl_tx_prepared.v'),
                scope='unbounded reset-epoch source and actual header FIFO conservation; unconstrained SRAM read values',
                healthy=audit_stage(a.prefix+'_final',None),faults={})
    for fault in ('tags','enqueue','reset'):result['faults'][fault]=audit_stage(f'{a.prefix}_{fault}_final',fault)
    result['reachability']=[audit_cover(w,prefix=a.prefix) for w in (8,16)]
    result['impossible_capture']=audit_cover(8,True,a.prefix)
    result.update(complete=True,properties_per_configuration=35,configurations=27,actual_fault_detections=6,
                  assumptions=['initial synchronous reset'],internal_control_cuts=0,full_payload_formal=False,full_top_sta=False,full_goal_complete=False)
    output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('healthy','faults')},indent=2))


if __name__=='__main__':main()

"""Verify observation binding preserves the actual DUT graph and every clock.
Run: python3 scripts/check_dl_basic_observations.py --before before.json --after connected.json --output audit.json
Outputs: exact actual-cone cell/state/clock audit; no data-path abstraction is accepted.
Next: combine this with the actual reset-base and full prior-state induction evidence.
"""
import argparse,json
from pathlib import Path


def actual_cone(module):
    cells=module['cells'];drivers={}
    for name,cell in cells.items():
        for port,direction in cell['port_directions'].items():
            if direction=='output':
                for bit in cell['connections'][port]:
                    if isinstance(bit,int):drivers.setdefault(bit,[]).append(name)
    roots={bit for name,net in module['netnames'].items() if name.startswith('DUT.') for bit in net['bits'] if isinstance(bit,int)}
    primary={bit for port in module['ports'].values() if port['direction']=='input' for bit in port['bits']}
    assert roots,'missing actual DUT observations'
    todo=list(roots);seen_bits=set();seen_cells=set()
    while todo:
        bit=todo.pop()
        if not isinstance(bit,int) or bit in seen_bits:continue
        seen_bits.add(bit)
        if bit in primary:
            assert bit not in drivers,('primary input internally driven',bit)
            continue
        owners=drivers.get(bit,[])
        assert len(owners)==1,('actual state/data has missing or multiple drivers',bit,owners)
        name=owners[0]
        if name in seen_cells:continue
        seen_cells.add(name)
        for port,direction in cells[name]['port_directions'].items():
            if direction=='input':todo.extend(cells[name]['connections'][port])
    return seen_cells


def compare_actual_graphs(before,after):
    binputs={n:p for n,p in before['ports'].items() if p['direction']=='input'}
    ainputs={n:p for n,p in after['ports'].items() if p['direction']=='input'}
    assert set(binputs)==set(ainputs),'primary input set changed'
    original=actual_cone(before);observed=actual_cone(after)
    assert original==observed,('actual cone cells changed',original-observed,observed-original)
    translation={}
    def pair(old,new,label):
        assert len(old)==len(new),('width changed',label)
        for a,b in zip(old,new):
            if isinstance(a,str):assert a==b,('actual constant changed',label,a,b)
            else:
                assert isinstance(b,int),('actual driven bit became a constant',label,a,b)
                if a in translation:assert translation[a]==b,('actual alias or driver changed',label,a,translation[a],b)
                else:translation[a]=b
    for n,p in binputs.items():pair(p['bits'],ainputs[n]['bits'],n)
    for n,net in before['netnames'].items():
        if n.startswith('DUT.'):
            assert n in after['netnames'],('actual net disappeared',n)
            pair(net['bits'],after['netnames'][n]['bits'],n)
    for n in original:
        old,new=before['cells'][n],after['cells'][n]
        assert old['type']==new['type'] and old['parameters']==new['parameters'],('actual cell semantics changed',n)
        assert old['port_directions']==new['port_directions'],('actual port directions changed',n)
        for port,direction in old['port_directions'].items():
            if direction=='output':pair(old['connections'][port],new['connections'][port],n+'.'+port)
    clocks=binputs['i_clk']['bits'];assert len(clocks)==1
    registers=[]
    for n in original:
        old,new=before['cells'][n],after['cells'][n]
        for port,bits in old['connections'].items():
            expected=[bit if isinstance(bit,str) else translation[bit] for bit in bits]
            assert expected==new['connections'][port],('actual cell connection changed',n,port)
        typ=old['type']
        assert not typ.startswith('KD28_') and not typ.startswith('$mem') and typ not in ('$anyseq','$anyconst','$assume'),('unexpanded actual cell or cutpoint',n,typ)
        if 'dff' in typ.lower() or 'latch' in typ.lower() or typ=='$ff':
            assert typ in ('$dff','$dffe','$sdff','$sdffe','$sdffce'),('asynchronous or unsupported actual state',n,typ)
            assert old['connections']['CLK']==clocks and int(old['parameters']['CLK_POLARITY'],2)==1,('actual clock is not common positive edge',n)
            registers.append((n,len(old['connections']['Q'])))
    assert registers,'actual registered storage absent'
    return dict(passed=True,actual_cells=len(original),actual_register_cells=len(registers),actual_state_bits=sum(n for _,n in registers),preserved_actual_bits=len(translation),primary_input_ports=len(binputs),primary_input_bits=sum(len(p['bits']) for p in binputs.values()),clock_count=1,actual_graph_unchanged=True,actual_state_or_Q_cutpoints=False)


STATE=(('reg_local_busy',1),('reg_local_sent',1),('reg_local_kind',3),('reg_local_word',32),('reg_remote_busy',1),('reg_remote_kind',3),('reg_remote_word',32),('reg_remote_rate',16),('reg_local_first',1),('cnt_remote_age',20),('reg_remote_missed',1),('reg_deadline_fault',1),('reg_protocol_fault',1),('reg_peer_rate_valid',1),('reg_peer_rate',16),('reg_peer_device_valid',1),('reg_peer_device_type',2),('reg_peer_device_id',10),('reg_peer_port_valid',1),('reg_peer_port',12))

def audit_graphs(before_path,after_path,contract_path,period):
    before=json.loads(Path(before_path).read_text())['modules']['dl_basic_properties']
    after=json.loads(Path(after_path).read_text())['modules']['dl_basic_properties']
    result=compare_actual_graphs(before,after)
    assert result['actual_register_cells']==20 and result['actual_state_bits']==156
    assert result['primary_input_ports']==18 and result['primary_input_bits']==104
    assert {n:int(v,2) for n,v in after['parameter_default_values'].items()}=={'C_PERIOD_PS':period}
    nets=after['netnames'];cells=after['cells']
    state=[]
    for n,w in STATE:
        bits=nets['DUT.'+n]['bits'];assert len(bits)==w;state.extend(bits)
    assert len(state)==len(set(state))==156 and nets['observed_state']['bits']==state
    actual=actual_cone(after)
    q=[b for n in actual if cells[n]['type']=='$dff' for b in cells[n]['connections']['Q']]
    assert len(q)==156 and set(q)==set(state),'unobserved actual sequential state'
    contract=json.loads(Path(contract_path).read_text())['interfaces']['ports']
    inputs={p['name']:p['width'] for p in contract if p['direction']=='input'}
    assert inputs=={n:len(p['bits']) for n,p in after['ports'].items() if p['direction']=='input'}
    outputs=[p for p in contract if p['direction']=='output'];assert len(outputs)==28
    output_bits=[b for p in reversed(outputs) for b in nets['DUT.'+p['name']]['bits']]
    assert len(output_bits)==194 and nets['observed']['bits']==output_bits
    groups=after['ports']['o_groups']['bits'];violation=after['ports']['o_violation']['bits']
    assert len(groups)==3 and len(violation)==1
    def driver(bits,op):
        matches=[c['connections'] for c in cells.values() if c['type']==op and c['connections'].get('Y')==bits]
        assert len(matches)==1,(bits,op);return matches[0]
    assert driver(violation,'$reduce_or')['A']==groups
    assert driver([groups[0]],'$logic_not')['A']==nets['bounds_ok']['bits']
    assert driver([groups[1]],'$logic_not')['A']==nets['state_ok']['bits']
    c=driver([groups[2]],'$ne');assert c['A']==output_bits and c['B']==nets['expected']['bits']
    c=driver(nets['state_ok']['bits'],'$eq');assert c['A']==state and len(c['B'])==156
    # Walk the full independent reference cone, including next-state drivers.
    ref=dict(after);ref['netnames']={n:v for n,v in nets.items() if not n.startswith('DUT.')}
    ref['netnames']['DUT.reference_expected']=nets['expected']
    ref['netnames']['DUT.reference_state']={'bits':c['B']}
    ref['netnames']['DUT.reference_bounds']=nets['bounds_ok']
    reference=actual_cone(ref)
    assert not (reference & actual),'reference depends on actual DUT state or logic'
    assert not any(c['type'] in ('$assume','$anyseq','$anyconst','$initstate') for c in cells.values())
    assert set(after['ports'])==set(inputs)|{'o_groups','o_violation'}
    result.update(actual_output_ports=28,actual_output_bits=194,complete_state_observed=True,reference_independent_from_actual_cone=True,reference_cells=len(reference))
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--before',type=Path,required=True);p.add_argument('--after',type=Path,required=True);p.add_argument('--contract',type=Path,required=True);p.add_argument('--period',type=int,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();result=audit_graphs(a.before,a.after,a.contract,a.period);a.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()

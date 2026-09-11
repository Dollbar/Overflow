"""Observe the actual read-bank state only while a corresponding read is pending.

Run: python3 scripts/add_uart_bank_observation.py GOLD_GATE.json OBSERVED.json
Outputs: fresh Yosys JSON adding one output/AND cell to each gold/gate module.
Next: prove the complete existing state/output/macro-port miter plus this relation.
No original driver/sink or state is changed; inactive unreset bank state is irrelevant.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path


def add_observation(design):
    if any(side not in design.get('modules',{}) for side in ('gold','gate')):
        raise ValueError('missing gold/gate module pair')
    result=deepcopy(design)
    for side in ('gold','gate'):
        module=result['modules'][side]
        if 'uart_active_read_bank' in module.get('ports',{}) or 'uart_active_bank_observer' in module.get('cells',{}):
            raise ValueError('bank observer already exists')
        bits=[]
        for name in ('Storage_Inst.Storage_Inst.read_bank_q','Storage_Inst.Fifo_Inst.reg_pending'):
            state=module.get('netnames',{}).get(name,{}).get('bits',[])
            if len(state)!=1 or type(state[0]) is not int or state[0]<2:
                raise ValueError('missing actual one-bit bank/pending state')
            bit=state[0]
            if any(bit in p['bits'] for p in module.get('ports',{}).values() if p['direction'] in ('input','inout')):
                raise ValueError('bank/pending cannot be a free state input')
            drivers=[c for c in module['cells'].values() if any(bit in c['connections'][p]
                     for p,d in c.get('port_directions',{}).items() if d=='output')]
            if len(drivers)!=1 or 'dff' not in drivers[0]['type'].lower():
                raise ValueError('bank/pending must retain exactly one actual flop driver')
            bits.append(bit)
        all_bits=[b for v in module.get('netnames',{}).values() for b in v['bits']]
        all_bits += [b for v in module.get('ports',{}).values() for b in v['bits']]
        all_bits += [b for c in module['cells'].values() for v in c['connections'].values() for b in v]
        out=max(b for b in all_bits if type(b) is int)+1
        name='uart_active_read_bank'
        module['ports'][name]={'direction':'output','bits':[out]}
        module['netnames'][name]={'hide_name':0,'bits':[out],'attributes':{}}
        module['cells']['uart_active_bank_observer']={
            'hide_name':0,'type':'$and','attributes':{},
            'parameters':{k:format(v,'032b') for k,v in dict(A_SIGNED=0,B_SIGNED=0,A_WIDTH=1,B_WIDTH=1,Y_WIDTH=1).items()},
            'port_directions':{'A':'input','B':'input','Y':'output'},
            'connections':{'A':[bits[0]],'B':[bits[1]],'Y':[out]}}
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('source',type=Path);p.add_argument('output',type=Path)
    args=p.parse_args()
    if args.output.exists():raise ValueError('refusing to overwrite observed JSON')
    result=add_observation(json.loads(args.source.read_text()))
    args.output.write_text(json.dumps(result)+'\n')
    print('UART_TX_ACTIVE_BANK_OBSERVED actual_state_preserved=1 new_state_inputs=0')


if __name__=='__main__':main()

"""Audit every Basic raw-state/public comparator and the real mapped clock graph.
Run: python3 scripts/check_dl_basic_mapping.py MITER.json CONTRACT.json
Outputs: exact 48bus/350bit comparison and state/clock inventory or failure.
Next: accept only reset and prior-full-trigger induction on this same mapped design.
"""
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from scripts.check_dl_basic_observations import STATE

def audit_mapping(module,contract):
    ports=module['ports'];nets=module['netnames'];cells=module['cells']
    inputs={p['name']:p['width'] for p in contract['interfaces']['ports'] if p['direction']=='input'}
    observed={p['name']:p['width'] for p in contract['interfaces']['ports'] if p['direction']=='output'}|dict(STATE)
    assert len(observed)==48 and sum(observed.values())==350
    assert {n:len(p['bits']) for n,p in ports.items() if p['direction']=='input'}=={'in_'+n:w for n,w in inputs.items()}
    input_bits=[b for n in inputs for b in ports['in_'+n]['bits']]
    assert len(input_bits)==len(set(input_bits))==104 and all(type(b) is int for b in input_bits)
    assert set(ports)=={'in_'+n for n in inputs}|{pre+n for n in observed for pre in ('gold_','gate_','cmp_')}|{'trigger'}
    drivers={}
    for n,c in cells.items():
        assert c['type'] not in ('$assume','$anyseq','$anyconst','$initstate') and not c.get('attributes',{}).get('blackbox')
        for pn,d in c['port_directions'].items():
            if d=='output':
                for b in c['connections'][pn]:
                    if type(b) is int:drivers.setdefault(b,[]).append(n)
    assert all(b not in drivers for b in input_bits),'a real primary input is driven internally'
    def driver(bits,typ):
        candidates=[c for c in cells.values() if c['type']==typ and c['connections'].get('Y')==bits]
        assert len(candidates)==1,(typ,bits);return candidates[0]['connections']
    cmpbits=[]
    for n,w in observed.items():
        a=ports['gold_'+n]['bits'];b=ports['gate_'+n]['bits'];out=ports['cmp_'+n]['bits']
        assert len(a)==len(b)==w and len(out)==1
        assert a==nets['gold.'+n]['bits'] and b==nets['gate.'+n]['bits']
        c=driver(out,'$eqx');assert (c['A']==a and c['B']==b) or (c['A']==b and c['B']==a),'comparison skips/reorders actual bits'
        cmpbits.extend(out)
    inv=driver(ports['trigger']['bits'],'$not');reduction=driver(inv['A'],'$reduce_and')
    assert len(cmpbits)==len(set(cmpbits))==48 and sorted(reduction['A'])==sorted(cmpbits)
    counts={}
    for side,typ in (('gold','$dff'),('gate','$_DFF_P_')):
        q=[];count=0
        for n,c in cells.items():
            if c['type']==typ and ('\\'+side+'.' in n):
                count+=1;connections=c['connections'];q+=connections['Q']
                clock=connections['CLK'] if typ=='$dff' else connections['C']
                assert clock==ports['in_i_clk']['bits']
                if typ=='$dff':assert int(c['parameters']['CLK_POLARITY'],2)==1
        statebits={b for n,_ in STATE for b in ports[side+'_'+n]['bits'] if type(b) is int}
        assert len(q)==len(set(q))==len(statebits) and set(q)==statebits
        counts[side]={'cells':count,'bits':len(q)}
    assert counts=={'gold':{'cells':20,'bits':156},'gate':{'cells':129,'bits':129}}
    all_seq=[c for c in cells.values() if 'dff' in c['type'].lower() or 'latch' in c['type'].lower() or c['type']=='$ff']
    assert len(all_seq)==149 and sum(len(c['connections']['Q']) for c in all_seq)==285
    return dict(passed=True,comparisons=48,compared_state_bits=156,compared_output_bits=194,all_comparisons_drive_trigger=True,primary_inputs=18,primary_input_bits=104,state=counts,common_raw_positive_clock=True,actual_state_or_Q_cutpoints=False)
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('miter',type=Path);p.add_argument('contract',type=Path);a=p.parse_args()
    print(json.dumps(audit_mapping(json.loads(a.miter.read_text())['modules']['dl_basic_mapping_miter'],json.loads(a.contract.read_text()))))
if __name__=='__main__':main()

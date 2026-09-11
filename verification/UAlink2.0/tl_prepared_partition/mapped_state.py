"""Complete FF observation for the mapped proof. Used by run_mapped.py;
run test_mapped_state.py for contract checks. No tool jobs or files are created
here. Next prove the relation on the emitted actual D/Q equations.
"""
import copy


def need(condition,message):
    if not condition:raise ValueError(message)


def observe(graph,fields):
    allowed={'$_DFF_P_','$_AND_','$_OR_','$_XOR_','$_NOT_','$_MUX_'}
    clock=graph['ports']['i_clk']['bits'];drivers=[];consumed=[];transitions={};remove=[]
    for port in graph['ports'].values():
        (drivers if port['direction']=='input' else consumed).extend(port['bits'])
    for name,cell in graph['cells'].items():
        need(cell['type'] in allowed,'unknown gate/state primitive '+cell['type'])
        for port,bits in cell['connections'].items():
            need(all(isinstance(b,int) or b in ('0','1') for b in bits),'X/Z actual logic connection')
            (drivers if cell['port_directions'][port]=='output' else consumed).extend(bits)
        if cell['type']=='$_DFF_P_':
            c=cell['connections'];need(c['C']==clock and len(c['Q'])==len(c['D'])==1,'actual positive clock/DFF width')
            need(c['Q'][0] not in transitions,'duplicate FF Q');transitions[c['Q'][0]]=c['D'][0];remove.append(name)
    need(len(drivers)==len(set(drivers)) and all(isinstance(b,int) for b in drivers),'multiple or constant drivers')
    driven=set(drivers)
    need(all(b in driven or b in ('0','1') for b in consumed),'undriven actual logic')
    state=[];indices={};aliases={}
    for name in fields:
        aliases[name]=[]
        for index,q in enumerate(graph['netnames'][name]['bits']):
            if q in ('0','1'):aliases[name].append(q);continue
            need(q in transitions,'semantic register is not actual FF Q: '+name)
            if q not in indices:
                indices[q]=len(state);state.append(dict(field=name,index=index,q=q,d=transitions[q]))
            aliases[name].append(indices[q])
    need(set(indices)==set(transitions) and bool(state),'unobserved actual FF')
    cut=copy.deepcopy(graph)
    for name in remove:del cut['cells'][name]
    need(not {'s_state','n_state'}&set(cut['ports']),'observation port collision')
    cut['ports']['s_state']=dict(direction='input',bits=[r['q'] for r in state])
    cut['ports']['n_state']=dict(direction='output',bits=[r['d'] for r in state])
    return cut,dict(state_bits=len(state),state=state,aliases=aliases,clock=clock,unobserved_state_bits=0)


def audit_cut(original,cut,layout):
    """Audit recorded graph equations independently of the transformation."""
    sequential={name:cell for name,cell in original['cells'].items() if cell['type']=='$_DFF_P_'}
    equations={name:cell for name,cell in original['cells'].items() if name not in sequential}
    need(cut['cells']==equations and cut['netnames']==original['netnames'],'actual combinational equations/aliases changed')
    need({n:p for n,p in cut['ports'].items() if n in original['ports']}==original['ports'],'original interface changed')
    need(set(cut['ports'])==set(original['ports'])|{'s_state','n_state'},'unaccounted cut port')
    actual={}
    for cell in sequential.values():
        c=cell['connections'];need(c['C']==original['ports']['i_clk']['bits'] and len(c['Q'])==len(c['D'])==1,'actual edge/clock')
        need(c['Q'][0] not in actual,'duplicate actual Q');actual[c['Q'][0]]=c['D'][0]
    recorded=layout['state'];q=[r['q'] for r in recorded];d=[r['d'] for r in recorded]
    need(len(q)==len(set(q))==len(actual)==layout['state_bits'] and set(q)==set(actual) and layout['unobserved_state_bits']==0,'incomplete actual state inventory')
    need(d==[actual[b] for b in q],'recorded next state differs from real D')
    need(cut['ports']['s_state']==dict(direction='input',bits=q) and cut['ports']['n_state']==dict(direction='output',bits=d),'state observation is not actual Q/D')
    for row in recorded:need(original['netnames'][row['field']]['bits'][row['index']]==row['q'],'semantic representative mismatch')
    for name,bits in layout['aliases'].items():
        restored=[q[b] if isinstance(b,int) else b for b in bits]
        need(restored==original['netnames'][name]['bits'],'semantic alias/constant mismatch')
    return len(q)

"""Independent packet-owner oracle; Python priority queues, not RTL scan arithmetic."""
from collections import deque,Counter
import random

class Oracle:
    def __init__(self,ports):
        self.ports=ports;self.owner=[None]*ports;self.priority=[deque(range(ports)) for _ in range(ports)]
    def step(self,rstn,valid,route,last,ready):
        if not rstn:
            self.__init__(self.ports);return 0
        selected=[]
        for e in range(self.ports):
            winner=self.owner[e]
            if winner is None:
                winner=next((s for s in self.priority[e] if (valid>>s)&1 and (route>>(s*self.ports+e))&1),None)
            selected.append(winner)
        bits=sum(1<<(e*self.ports+s) for e,s in enumerate(selected) if s is not None)
        for e,s in enumerate(selected):
            if s is not None and (valid>>s)&1 and (route>>(s*self.ports+e))&1:
                if (ready>>e)&1 and (last>>s)&1:
                    self.owner[e]=None
                    while self.priority[e][0]!=s:self.priority[e].rotate(-1)
                    self.priority[e].rotate(-1)
                else:self.owner[e]=s
        return bits

def vectors(ports,seed=31907):
    oracle=Oracle(ports);rows=[];phases=Counter();rng=random.Random(seed+ports)
    all_sources=(1<<ports)-1
    def route_map(targets):return sum(1<<(s*ports+e) for s,e in enumerate(targets) if e is not None)
    to_zero=route_map([0]*ports)
    def emit(phase,valid=0,route=0,last=0,ready=0,rstn=1,want=None,want_owned=None):
        assert all(((route>>(s*ports))&all_sources).bit_count()<=1 for s in range(ports))
        owned=sum(1<<e for e,s in enumerate(oracle.owner) if s is not None) if rstn else 0
        if want_owned is not None:assert owned==want_owned,(ports,phase,owned,want_owned)
        actual=oracle.step(rstn,valid,route,last,ready)
        if want is not None:assert actual==want,(ports,phase,hex(actual),hex(want))
        rows.append(dict(phase=phase,rstn=rstn,valid=valid,route=route,last=last,ready=ready,expected=actual,owned=owned));phases[phase]+=1
        return actual
    emit('power_reset',rstn=0,want=0)
    high=1<<(ports-1)
    emit('first_stall',valid=high,route=to_zero,last=high,ready=0,want=high,want_owned=0)
    emit('first_stall_competitor',valid=all_sources,route=to_zero,last=all_sources,ready=0,want=high,want_owned=1)
    emit('owner_bubble',valid=all_sources^high,route=to_zero,last=all_sources,ready=all_sources,want=high,want_owned=1)
    emit('owner_route_invalid',valid=all_sources,route=to_zero&~(1<<((ports-1)*ports)),last=all_sources,ready=all_sources,want=high)
    emit('route_still_invalid',valid=all_sources,route=to_zero&~(1<<((ports-1)*ports)),last=all_sources,ready=all_sources,want=high)
    emit('route_restore_and_finish',valid=all_sources,route=to_zero,last=all_sources,ready=all_sources,want=high)
    emit('next_after_last_wrap',valid=all_sources,route=to_zero,last=all_sources,ready=all_sources,want=1,want_owned=0)
    emit('reset_with_ready',valid=all_sources,route=to_zero,last=all_sources,ready=all_sources,rstn=0,want=0)
    # Packet lengths vary by source; no switch is permitted during its body or last-beat stall.
    for src in range(ports):
        choice=1<<src
        emit('packet_first',valid=all_sources,route=to_zero,last=0,ready=all_sources,want=choice)
        emit('packet_body_stall',valid=all_sources,route=to_zero,last=0,ready=0,want=choice)
        emit('packet_body_bubble',valid=all_sources^choice,route=to_zero,last=0,ready=all_sources,want=choice)
        emit('packet_last_stall',valid=all_sources,route=to_zero,last=all_sources,ready=0,want=choice)
        emit('packet_last_take',valid=all_sources,route=to_zero,last=all_sources,ready=all_sources,want=choice)
    emit('midpacket_reset_setup',valid=high,route=to_zero,last=0,ready=0,want=high)
    emit('midpacket_reset',valid=all_sources,route=to_zero,last=0,ready=all_sources,rstn=0,want=0)
    emit('after_reset_no_owner',valid=all_sources,route=to_zero,last=all_sources,ready=all_sources,want=1)
    # Continuous single-beat contenders: exactly one grant per source every PORTS completions.
    emit('fairness_reset',rstn=0,want=0)
    service=[0]*ports;last_at=[-ports+s for s in range(ports)];max_wait=0
    for turn in range(ports*12):
        selected=emit('fairness_all_contend',valid=all_sources,route=to_zero,last=all_sources,ready=all_sources,want=1<<(turn%ports))
        source=selected.bit_length()-1;service[source]+=1;max_wait=max(max_wait,turn-last_at[source]);last_at[source]=turn
    assert service==[12]*ports and max_wait==ports
    # Exercise independent simultaneous destinations and an explicit source/egress transpose.
    emit('parallel_reset',rstn=0,want=0)
    targets=[(s+1)%ports for s in range(ports)]
    parallel=route_map(targets)
    expected=sum(1<<(e*ports+s) for s,e in enumerate(targets))
    emit('parallel_first_stall',valid=all_sources,route=parallel,last=0,ready=0,want=expected)
    emit('parallel_bubbles',valid=0,route=parallel,last=all_sources,ready=all_sources,want=expected)
    emit('parallel_finish',valid=all_sources,route=parallel,last=all_sources,ready=all_sources,want=expected)
    # Source packet generator advances only on external owner+valid+route+ready handshakes.
    remaining=[0]*ports;targets=[None]*ports
    for tick in range(1800):
        if tick in (377,1111):
            emit('random_reset',rstn=0,want=0);remaining=[0]*ports;targets=[None]*ports;continue
        for source in range(ports):
            if remaining[source]==0 and rng.randrange(4)!=0:
                remaining[source]=rng.randrange(1,7);targets[source]=rng.randrange(ports)
        valid=sum(1<<s for s in range(ports) if remaining[s]>0 and rng.randrange(5)!=0)
        last=sum(1<<s for s in range(ports) if remaining[s]==1)
        ready=rng.randrange(1<<ports);route=route_map(targets)
        selected=emit('random_packets',valid=valid,route=route,last=last,ready=ready)
        for source in range(ports):
            if remaining[source] and (valid>>source)&1:
                e=targets[source]
                if (selected>>(e*ports+source))&1 and (ready>>e)&1:
                    remaining[source]-=1
                    if remaining[source]==0:targets[source]=None
    for tick in range(ports*8):
        valid=sum(1<<s for s in range(ports) if remaining[s]>0)
        last=sum(1<<s for s in range(ports) if remaining[s]==1)
        selected=emit('drain',valid=valid,route=route_map(targets),last=last,ready=all_sources)
        for source in range(ports):
            if remaining[source] and (selected>>(targets[source]*ports+source))&1:
                remaining[source]-=1
                if remaining[source]==0:targets[source]=None
    assert not any(remaining) and all(owner is None for owner in oracle.owner)
    emit('drained_idle',want=0,want_owned=0)
    return rows,dict(phases=phases,fairness_service=service,max_wait_completed_packets=max_wait,seed=seed+ports)

def pack(row,ports):
    square=ports*ports
    return row['route']|(row['valid']<<square)|(row['last']<<(square+ports))|(row['ready']<<(square+2*ports))|(row['rstn']<<(square+3*ports))|(row['expected']<<(square+3*ports+1))|(row['owned']<<(2*square+3*ports+1))

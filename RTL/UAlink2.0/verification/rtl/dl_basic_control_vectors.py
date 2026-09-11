"""Generate every real Basic control edge from the independent event adapter.
Run: python3 verification/rtl/dl_basic_control_vectors.py --output vectors.mem --summary vectors.json
Outputs: complete input/pre/post rows and event counts; next: actual RTL simulation.
"""
import argparse
from dataclasses import fields
import json
from pathlib import Path
import random
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from model.ualink.dl_basic_control import DLBasicControl,DLBasicSignals,INPUTS,KINDS

WIDTHS=(1,1,1,1,4,128,1,1,1,1,1,1,1,1,1,1,1,16,1,2,10,1,12,1,1,1,1,1)
EVENTS=('local_start','local_commit','local_done','reply_done','rx_request','rx_noop','rx_unhandled',
        'rx_unsupported','rx_unmatched_ack','rx_overlap','peer_rate_update','deadline_miss','error')


def pack_output(value):
    result=0
    for field,width in zip(fields(DLBasicSignals),WIDTHS,strict=True):
        v=int(getattr(value,field.name));assert 0<=v<(1<<width)
        result=(result<<width)|v
    return result


def pack_input(values):
    result=0
    for name,width in INPUTS:
        v=int(values.get(name,0));v=1-v if name=='reset' else v
        result=(result<<width)|v
    return result


def campaign(period,seed,cycles):
    model=DLBasicControl(period);rng=random.Random(seed);lines=[];counts=dict.fromkeys(EVENTS,0)
    def edge(**inputs):
        before=model.tick(**inputs);after=model.observe(**inputs)
        lines.append(f'{pack_input(inputs):x} {pack_output(before):x} {pack_output(after):x}\n')
        for name in EVENTS:counts[name]+=int(getattr(before,name))
        return before
    def reset():edge(reset=True,local_valid=True,local_kind=7,rx_valid=True,rx_word=0xFFFFFFFF,source_take=15)
    reset()
    for kind in KINDS:
        cfg=dict(device_valid=True,device_id=0x155,device_type=1,port_valid=True,port=0xABC,
                 folding=True,tx_ready_advertised=True,symbols_valid=True,tx_limit_valid=True,tx_limit=3125)
        edge(local_valid=True,local_kind=kind,local_rate=3125,**cfg)
        for _ in range(3):edge(local_valid=True,local_kind=6,**cfg)
        edge(source_take=1<<KINDS.index(kind),rx_valid=True,rx_word=(kind<<6)|0x1000,**cfg)
        edge(rx_valid=True,rx_word=(kind<<6)|0xFFFFFE03|0x1000,**cfg)
        edge(rx_valid=True,rx_word=(0x0C350100 if kind==4 else kind<<6),**cfg)
        edge(source_take=1<<KINDS.index(kind),**cfg)
    reset()
    edge(local_valid=True,local_kind=5,device_valid=True,device_id=3,device_type=1)
    edge(rx_valid=True,rx_word=0x140,device_valid=True,device_id=9)
    edge(source_take=4);edge(source_take=4);edge(rx_valid=True,rx_word=0x80091140)
    edge(local_valid=True,local_kind=6,rx_valid=True,rx_word=0x180,port_valid=True,port=11)
    edge(source_take=8,rx_valid=True,rx_word=0x140)
    edge(source_take=12);edge(source_take=8);edge(source_take=4)
    reset()
    edge(rx_valid=True,rx_word=0x0C350100)
    edge(local_valid=True,local_kind=4,local_rate=31250)
    edge(tx_limit_valid=True,tx_limit=3126,source_take=2)
    edge(tx_limit_valid=True,tx_limit=3125)
    edge(source_take=2);edge(source_take=2,tx_limit_valid=True,tx_limit=3125)
    edge(source_take=2);edge(rx_valid=True,rx_word=0x12341100)
    for delta in (-1,0,1,3):
        reset();edge(rx_valid=True,rx_word=0x180)
        delay=max(1,1_000_000//period+delta)
        for _ in range(delay-1):edge()
        edge(source_take=8)
        for _ in range(3):edge()
    reset();edge(rx_valid=True,rx_word=0x180)
    for _ in range(1_000_000//period+8):edge()
    edge(rx_valid=True,rx_word=0x140);edge(source_take=8,rx_valid=True,rx_word=0x140);edge(source_take=4)
    for _ in range(cycles):
        kind=rng.choice(KINDS)
        if rng.randrange(3)==0:word=(kind<<6)|(rng.getrandbits(16)<<16)|(rng.randrange(2)<<12)|((rng.getrandbits(7)&0x77)<<9)
        else:word=rng.getrandbits(32)
        cfg=dict(reset=rng.randrange(113)==0,local_valid=rng.randrange(3)==0,local_kind=rng.randrange(8),local_rate=rng.getrandbits(16),
                 device_valid=bool(rng.randrange(2)),device_id=rng.randrange(1024),device_type=rng.randrange(2),
                 port_valid=bool(rng.randrange(2)),port=rng.randrange(4096),folding=bool(rng.randrange(2)),
                 tx_ready_advertised=bool(rng.randrange(2)),symbols_valid=bool(rng.randrange(2)),
                 tx_limit_valid=bool(rng.randrange(2)),tx_limit=rng.getrandbits(16),rx_valid=rng.randrange(3)==0,rx_word=word)
        offer=model.observe(**cfg).source_pending
        take=rng.choice([0]+[1<<i for i in range(4) if offer&(1<<i)])
        if rng.randrange(9)==0:take=rng.randrange(16)
        edge(source_take=take,**cfg)
    reset();edge()
    return lines,dict(rows=len(lines),period_ps=period,seed=seed,random_cycles=cycles,input_bits=sum(w for _,w in INPUTS),
                      output_bits=sum(WIDTHS),events=counts,full_actual_clock=True)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);p.add_argument('--summary',type=Path,required=True)
    p.add_argument('--period-ps',type=int,default=640);p.add_argument('--seed',type=int,default=17);p.add_argument('--cycles',type=int,default=4000)
    a=p.parse_args();lines,summary=campaign(a.period_ps,a.seed,a.cycles)
    a.output.write_text(''.join(lines));a.summary.write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary))

"""Cycle adapter over the independent Basic event/FIFO reference.

Only public event-model operations establish queue/ownership behavior. The
adapter freezes old-state handshake decisions and orders same-edge events.
"""
from copy import deepcopy
from dataclasses import dataclass
from model.ualink.dl_basic_message import DLBasicController

INPUTS=(('reset',1),('local_valid',1),('local_kind',3),('local_rate',16),
        ('device_valid',1),('device_id',10),('device_type',1),('port_valid',1),('port',12),
        ('folding',1),('tx_ready_advertised',1),('symbols_valid',1),('tx_limit_valid',1),('tx_limit',16),
        ('rx_valid',1),('rx_word',32),('source_take',4))
KINDS=(1,4,5,6)


@dataclass(frozen=True)
class DLBasicSignals:
    local_ready:bool=False
    local_pending:bool=False
    local_waiting:bool=False
    remote_pending:bool=False
    source_pending:int=0
    source_words:int=0
    local_start:bool=False
    local_commit:bool=False
    local_done:bool=False
    reply_done:bool=False
    rx_request:bool=False
    rx_noop:bool=False
    rx_unhandled:bool=False
    rx_unsupported:bool=False
    rx_unmatched_ack:bool=False
    rx_overlap:bool=False
    peer_rate_valid:bool=False
    peer_rate:int=0
    peer_device_valid:bool=False
    peer_device_type:int=0
    peer_device_id:int=0
    peer_port_valid:bool=False
    peer_port:int=0
    peer_rate_update:bool=False
    deadline_miss:bool=False
    deadline_fault:bool=False
    protocol_fault:bool=False
    error:bool=False


class DLBasicControl:
    def __init__(self,clock_period_ps=640):
        if type(clock_period_ps) is not int or not 1<=clock_period_ps<=1_000_000_000:
            raise ValueError('clock period must be1..1,000,000,000 integer ps')
        self.period_ps=clock_period_ps
        self._edge=0
        self._reference=DLBasicController()
        self._waiting=False
        self._protocol_fault=False

    def _inputs(self,provided):
        known=dict(INPUTS)
        if set(provided)-set(known):raise ValueError('unknown native input')
        values={name:(False if width==1 and name!='device_type' else 0) for name,width in INPUTS}
        values.update(provided)
        for name,width in INPUTS:
            v=values[name]
            if width==1 and name!='device_type':
                if type(v) is not bool:raise ValueError(name+' must be boolean')
            elif type(v) is not int or not 0<=v<(1<<width):raise ValueError(name+' width/type')
        return values

    def observe(self,**inputs):
        return deepcopy(self)._apply(self._inputs(inputs))

    def tick(self,**inputs):
        output=self._apply(self._inputs(inputs))
        self._edge+=1
        return output

    def _apply(self,x):
        r=self._reference
        if x['reset']:
            r.reset();self._waiting=False;self._protocol_fault=False
            return DLBasicSignals()
        r.device_id=x['device_id'] if x['device_valid'] else None
        r.device_type=x['device_type']
        r.port=x['port'] if x['port_valid'] else None
        r.folding=x['folding'];r.tx_ready_advertised=x['tx_ready_advertised']
        r.set_tx_limit(x['tx_limit'] if x['tx_limit_valid'] else 65535)
        now=self._edge*self.period_ps
        previous_misses=r.deadline_misses
        old_protocol_fault=self._protocol_fault
        r.advance_to(now)
        offered=r.offers()
        if not x['tx_limit_valid'] and offered.get(4,0)&0x1000:
            offered.pop(4)
        pending=sum(1<<i for i,kind in enumerate(KINDS) if kind in offered)
        words=sum(word<<(32*KINDS.index(kind)) for kind,word in offered.items())
        kind=x['local_kind'];supported=kind in KINDS
        capability=kind!=1 or (x['folding'] and x['tx_ready_advertised'] and x['symbols_valid'])
        ready=not r.local_pending and supported and capability
        state=dict(local_ready=ready,local_pending=r.local_pending,local_waiting=self._waiting,
                   remote_pending=r.remote_pending,source_pending=pending,source_words=words,
                   peer_rate_valid=r.peer_rate is not None,peer_rate=r.peer_rate or 0,
                   peer_device_valid=r.peer_device is not None,
                   peer_device_type=r.peer_device[0] if r.peer_device else 0,
                   peer_device_id=r.peer_device[1] if r.peer_device else 0,
                   peer_port_valid=r.peer_port is not None,peer_port=r.peer_port or 0,
                   deadline_fault=previous_misses>0,protocol_fault=old_protocol_fault,
                   deadline_miss=r.deadline_misses!=previous_misses)
        take=x['source_take']
        bad_take=bool(take and (take.bit_count()!=1 or (take&pending)!=take))
        word=x['rx_word'];rx_kind=(word>>6)&7
        ack_before_commit=x['rx_valid'] and bool(word&0x1000) and rx_kind!=0
        result=r.receive(word,now_ps=now) if ack_before_commit else None
        if result=='ack':self._waiting=False
        state['local_done']=result=='ack'
        if take and not bad_take:
            selected=KINDS[take.bit_length()-1]
            sent=r.commit(selected,now_ps=now)
            assert sent==offered[selected]
            if sent&0x1000:state['reply_done']=True
            else:state['local_commit']=True;self._waiting=True
        if x['rx_valid'] and not ack_before_commit:
            result=r.receive(word,now_ps=now)
        state.update(rx_request=result=='request',rx_noop=result=='noop',rx_unhandled=result=='unhandled',
                     rx_unsupported=result=='unsupported',rx_unmatched_ack=result=='unmatched_ack',
                     rx_overlap=result=='remote_overlap',peer_rate_update=result=='request' and rx_kind==4)
        start=x['local_valid'] and ready
        if start:
            if kind==4:accepted=r.request_rate(x['local_rate'])
            elif kind==5:accepted=r.request_device_id()
            elif kind==6:accepted=r.request_port()
            else:accepted=r.request_tx_ready(symbols_valid=x['symbols_valid'])
            assert accepted
            self._waiting=False
        state['local_start']=start
        state['error']=bad_take or (x['local_valid'] and not supported) or result in ('unmatched_ack','remote_overlap')
        self._protocol_fault|=state['error']
        return DLBasicSignals(**state)

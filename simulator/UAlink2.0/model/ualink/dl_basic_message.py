"""DL/PL2.0 Basic request ownership and bounded source admission reference.

Time is supplied in integer picoseconds at the real message boundary. Pacing
enforcement is an external input; this is not a PLL, PHY or complete DL model.
"""
from collections import deque
from dataclasses import dataclass


def _uint(value, width, name):
    if type(value) is not int or not 0 <= value < (1 << width):
        raise ValueError(f'{name} must be an unsigned {width}-bit integer')


@dataclass
class _Frame:
    kind: int
    word: int
    reply: bool = False
    received_ps: int | None = None
    rate: int | None = None
    sent: bool = False
    missed: bool = False


class DLBasicController:
    """One local request and one independent remote reply obligation per class.

    Accepted local work occupies the single local slot before transmission.
    Per-type FIFOs have at most two entries: one local request and one remote
    response. No queue reorders an already offered head. Peer overlap is an
    input protocol diagnostic, not an invented on-wire error response.
    """
    def __init__(self, *, device_id=None, device_type=0, port=None,
                 folding=False, tx_ready_advertised=False):
        if device_id is not None:
            _uint(device_id,10,'device_id')
        if port is not None:
            _uint(port,12,'port')
        _uint(device_type,1,'device_type')
        if type(folding) is not bool or type(tx_ready_advertised) is not bool:
            raise ValueError('capabilities must be booleans')
        if tx_ready_advertised and not folding:
            raise ValueError('Tx Ready advertisement requires folding support')
        self.device_id=device_id
        self.device_type=device_type
        self.port=port
        self.folding=folding
        self.tx_ready_advertised=tx_ready_advertised
        self._now=0
        self.reset()

    def reset(self):
        """Clear protocol ownership while keeping local configuration and time."""
        self._local=None
        self._remote=None
        self._queues={kind:deque() for kind in (1,4,5,6)}
        self._tx_limit=None
        self.peer_rate=None
        self.peer_device=None
        self.peer_port=None
        self.completed_requests=0
        self.protocol_errors=0
        self.deadline_misses=0
        self.response_latencies_ps=[]

    @property
    def local_pending(self):
        return self._local is not None

    @property
    def remote_pending(self):
        return self._remote is not None

    def advance_to(self, now_ps):
        """Observe an absolute stable time; deadline violation never drops work."""
        if type(now_ps) is not int or now_ps < self._now:
            raise ValueError('time must be an integer and cannot go backwards')
        self._now=now_ps
        remote=self._remote
        if remote is not None and not remote.missed and now_ps-remote.received_ps > 1_000_000:
            remote.missed=True
            self.deadline_misses+=1

    def set_tx_limit(self, rate):
        """Declare the already enforced external pacing ceiling in Rate units."""
        _uint(rate,16,'tx_limit')
        self._tx_limit=rate

    def _local_request(self, kind, word):
        if self._local is not None:
            return False
        frame=_Frame(kind,word)
        self._local=frame
        self._queues[kind].append(frame)
        return True

    def request_rate(self, rate):
        """Rate is an encoded normalized throughput, not an arbitrary clock Hz."""
        _uint(rate,16,'rate')
        return self._local_request(4,(rate<<16)|0x100)

    def _identity_word(self, kind, ack):
        header=(kind<<6)|(int(ack)<<12)
        if kind==5:
            return header|(self.device_type<<29)|(0 if self.device_id is None else (1<<31)|(self.device_id<<16))
        return header|(0 if self.port is None else (1<<31)|(self.port<<16))

    def request_device_id(self):
        return self._local_request(5,self._identity_word(5,False))

    def request_port(self):
        return self._local_request(6,self._identity_word(6,False))

    def request_tx_ready(self, *, symbols_valid):
        if type(symbols_valid) is not bool:
            raise ValueError('symbols_valid must be a boolean')
        if not self.folding or not self.tx_ready_advertised or not symbols_valid:
            return False
        return self._local_request(1,0x40)

    def _learn_identity(self, kind, word):
        if kind==5:
            # Reserved Type encodings are retained as raw observations, never
            # generated as a locally configured device type or accepted policy.
            self.peer_device=(((word>>29)&3),(word>>16)&1023) if word&(1<<31) else None
        elif kind==6:
            self.peer_port=(word>>16)&4095 if word&(1<<31) else None

    def receive(self, word, *, now_ps):
        """Receive one reliable, framed DWORD; reserved fields do not match ACKs."""
        _uint(word,32,'word')
        self.advance_to(now_ps)
        kind=(word>>6)&7
        if (word>>2)&15 or kind not in (0,1,4,5,6):
            return 'unhandled'
        if kind==0:
            return 'noop'
        if kind==1 and not self.folding:
            return 'unsupported'
        if word&0x1000:
            if self._local is None or not self._local.sent or self._local.kind!=kind:
                self.protocol_errors+=1
                return 'unmatched_ack'
            self._learn_identity(kind,word)
            self._local=None
            self.completed_requests+=1
            return 'ack'
        if self._remote is not None:
            self.protocol_errors+=1
            return 'remote_overlap'
        rate=(word>>16)&65535 if kind==4 else None
        if kind==4:
            self.peer_rate=rate
        self._learn_identity(kind,word)
        response=self._identity_word(kind,True) if kind in (5,6) else (kind<<6)|0x1000
        frame=_Frame(kind,response,reply=True,received_ps=now_ps,rate=rate)
        self._remote=frame
        self._queues[kind].append(frame)
        return 'request'

    def _eligible(self, frame):
        return not (frame.reply and frame.kind==4 and
                    (self._tx_limit is None or self._tx_limit > frame.rate))

    def offers(self):
        """Stable queue heads keyed by mtype; no service is implied by this read."""
        return {kind:queue[0].word for kind,queue in self._queues.items()
                if queue and self._eligible(queue[0])}

    def commit(self, kind, *, now_ps):
        """Commit only an actually serviced DWORD; caller owns source arbitration."""
        if type(kind) is not int or kind not in self._queues:
            raise ValueError('kind must be a supported Basic request type')
        self.advance_to(now_ps)
        queue=self._queues[kind]
        if not queue or not self._eligible(queue[0]):
            return None
        frame=queue.popleft()
        if frame.reply:
            self.response_latencies_ps.append(now_ps-frame.received_ps)
            self._remote=None
        else:
            frame.sent=True
        return frame.word

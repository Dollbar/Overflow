"""Common 2.6/4.3 single-channel receive storage and credit handoff.

Opaque payloads are not TL transactions: burst legality, parity and RAS remain
outside this block. Diagnostics are local observation codes, not wire encodings.
Snapshots describe stable outputs; a peer consumes them BEFORE this step.
"""

from dataclasses import dataclass

from .receive_fifo import ReceiveFifo
from .upli_connection import ConnectionSignals
from .upli_credit import Beat, CreditReturn
from .upli_credit_initialization import InitialCreditPublisher
from .upli_credit_return import CreditReturnQueue


@dataclass(frozen=True)
class ReceivedBeat:
    beat: Beat
    payload: int


@dataclass(frozen=True)
class ReceiveHead:
    received: ReceivedBeat | None = None
    ready: bool = False


@dataclass(frozen=True)
class ReceiveSignals:
    returns: tuple[CreditReturn, ...]
    done: int
    counts: tuple[int, ...]
    pending: tuple[int, ...]


@dataclass(frozen=True)
class ReceiveStep:
    accepted: bool = False
    retired: ReceivedBeat | None = None
    diagnostic: int = 0


class UpliReceiveChannel:
    """One native beat input, five independent accounts per enabled port.

    Retirement atomically removes a real word and stores its original metadata
    in the return queue. Old FIFO capacity and old queue readiness are binding;
    neither a simultaneous pop nor a registered grant is a bypass opportunity.
    """

    def __init__(self, capacities, num_ports, payload_width=32, credit_width=4,
                 return_depth=4, channel="req"):
        if type(payload_width) is not int:
            raise TypeError("payload_width must be an integer")
        if payload_width < 1:
            raise ValueError("payload_width must be positive")
        capacities = tuple(capacities)
        self._initializer = InitialCreditPublisher(capacities, num_ports, credit_width, channel)
        self._return_queue = CreditReturnQueue(num_ports, return_depth, channel)
        self.num_ports, self.channel, self.payload_width = num_ports, channel, payload_width
        self.storage_width = ((payload_width+3+7)//8)*8
        self._fifos = tuple(ReceiveFifo(depth, self.storage_width) if depth else None for depth in capacities)
        self._connection = ConnectionSignals()

    @property
    def outputs(self):
        initial = self._initializer.outputs
        normal = self._return_queue.outputs
        if {grant.port for grant in initial.returns} & {grant.port for grant in normal}:
            raise AssertionError("initial and normal credit reservations overlap")
        return ReceiveSignals(tuple(sorted(initial.returns+normal, key=lambda grant: grant.port)), initial.done,
                              tuple(fifo.outputs.count if fifo else 0 for fifo in self._fifos),
                              self._return_queue.pending)

    @staticmethod
    def _select(port, account):
        if type(port) is not int or type(account) is not int:
            raise TypeError("consumer port and account must be integers")
        if not 0 <= port < 4 or not 0 <= account < 8:
            raise ValueError("consumer fields must fit two-bit port and three-bit account")

    def peek(self, port, account):
        self._select(port, account)
        if port >= self.num_ports or account >= 5:
            return ReceiveHead()
        fifo = self._fifos[port*5+account]
        if fifo is None or not fifo.outputs.valid:
            return ReceiveHead()
        word = fifo.outputs.data
        beat = Beat(port, self.channel, (word >> self.payload_width) & 3,
                    bool((word >> (self.payload_width+2)) & 1))
        return ReceiveHead(ReceivedBeat(beat, word & ((1 << self.payload_width)-1)),
                           self._return_queue.ready(port))

    def _validate(self, connection, incoming, consumer, consume):
        if not isinstance(connection, ConnectionSignals):
            raise TypeError("a stable ConnectionSignals snapshot is required")
        if type(consume) is not bool:
            raise TypeError("consume must be a boolean")
        if consumer is not None:
            if not isinstance(consumer, tuple) or len(consumer) != 2:
                raise TypeError("consumer must be a (port, account) tuple or None")
            self._select(*consumer)
        if incoming is not None:
            if not isinstance(incoming, ReceivedBeat) or not isinstance(incoming.beat, Beat):
                raise TypeError("incoming must contain a Beat and integer payload")
            beat = incoming.beat
            if any(type(value) is not int for value in (beat.port, beat.vc, incoming.payload)):
                raise TypeError("port, VC and payload must be integers")
            if type(beat.pool) is not bool:
                raise TypeError("Pool must be a boolean")
            if not 0 <= beat.port < 4 or not 0 <= beat.vc < 4 or beat.channel != self.channel:
                raise ValueError("incoming fields exceed the native shape or identify another channel")
            if not 0 <= incoming.payload < (1 << self.payload_width):
                raise ValueError("payload does not fit the configured width")
        for name in ("orig_req", "comp_ack", "comp_req", "orig_ack"):
            if getattr(self._connection, name) and not getattr(connection, name):
                raise ValueError("connection signals cannot withdraw before UPLI reset")

    def step(self, connection, incoming=None, consumer=None, consume=False, reset=False):
        if type(reset) is not bool:
            raise TypeError("reset must be a boolean")
        if reset:
            self._initializer.step(None, reset=True)
            self._return_queue.step(reset=True)
            for fifo in self._fifos:
                if fifo is not None:
                    fifo.step(reset=True)
            self._connection = ConnectionSignals()
            return ReceiveStep()
        self._validate(connection, incoming, consumer, consume)
        before = self.outputs
        diagnostic, write_slot, write_word = 0, None, None
        if incoming is not None:
            beat = incoming.beat
            slot = beat.port*5 + (4 if beat.pool else beat.vc)
            if beat.port >= self.num_ports:
                diagnostic = 1
            elif not connection.beats_enabled:
                diagnostic = 2
            elif not before.done & (1 << beat.port):
                diagnostic = 3
            elif self._fifos[slot] is None or not self._fifos[slot].outputs.ready:
                diagnostic = 4
            else:
                write_slot = slot
                write_word = incoming.payload | (beat.vc << self.payload_width) | (int(beat.pool) << (self.payload_width+2))
        head = self.peek(*consumer) if consumer is not None else ReceiveHead()
        retired = head.received if consume and head.ready else None
        read_slot = consumer[0]*5+consumer[1] if retired is not None else None
        allowed = connection.comp_connected if self.channel in ("req", "orig_data") else connection.orig_connected
        self._initializer.step(connection)
        queued = self._return_queue.step(None if retired is None else retired.beat,
                                         before.done if allowed else 0)
        if queued.accepted != (retired is not None):
            raise AssertionError("payload release and original metadata retention diverged")
        for slot, fifo in enumerate(self._fifos):
            if fifo is not None:
                result = fifo.step(write_word if slot == write_slot else None, consume=slot == read_slot)
                if result.accepted != (slot == write_slot) or (result.consumed is not None) != (slot == read_slot):
                    raise AssertionError("FIFO ownership differs from the pre-edge reservation")
        self._connection = connection
        return ReceiveStep(write_slot is not None, retired, diagnostic)

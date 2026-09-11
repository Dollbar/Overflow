"""Cycle wrapper over the independently tested UART reset event reference.

The event model supplies protocol phase, encoding, ordered response ownership
and absolute-time deadlines. This wrapper defines clock-edge ordering and finite
queue failure. It never reads RTL state. Queue observations use unbounded event
counts; run-out observations use committed-word counts rather than RTL countdown.
"""
from copy import deepcopy
from dataclasses import dataclass

from model.ualink.uart_reset import UARTResetSequencer


@dataclass(frozen=True)
class UARTResetSignals:
    local_ready: bool = False
    stream_reset: bool = False
    block_messages: bool = False
    tx_pending: bool = False
    tx_word: int = 0
    tx_kind: int = 0
    waiting: bool = False
    noops_left: int = 0
    response_count: int = 0
    local_start: bool = False
    local_done: bool = False
    retry: bool = False
    reply_done: bool = False
    fault: bool = False
    error: bool = False


class UARTResetControl:
    """Declared-period synchronous reference; fault recovery requires global reset.

    A fresh local request suppresses the old maintenance offer. SUCCESS observed
    in WAIT precedes elapsed time, so it wins at the deadline; an early response
    on the Request commit edge is ignored. Time advances before actual service,
    so the Request deadline begins at its actual commit edge. Peer requests are
    queued after any committed response, allowing full-queue replacement.
    """

    def __init__(self, clock_period_ps=640, response_depth=4):
        if type(clock_period_ps) is not int or not 1 <= clock_period_ps <= 1_000_000_000:
            raise ValueError('clock period must be an integer in1..1000000000ps')
        if type(response_depth) is not int or not 1 <= response_depth <= 16:
            raise ValueError('response depth must be an integer in1..16')
        self.period_ps = clock_period_ps
        self.response_depth = response_depth
        self._clear()

    def _clear(self):
        self._seq = UARTResetSequencer()
        self._seq.release_reset()
        self._requests_seen = 0
        self._responses_sent = 0
        self._noops_sent = 0
        self._fault = False

    def observe(self, *, reset=False, local_request=False, local_all=False,
                rx_request=False, request_all=False, rx_response=False,
                response_status=0, tx_take=False):
        for name, value in (('reset', reset), ('local_request', local_request),
                            ('local_all', local_all), ('rx_request', rx_request),
                            ('request_all', request_all), ('rx_response', rx_response),
                            ('tx_take', tx_take)):
            if type(value) is not bool:
                raise ValueError(name+' must be boolean')
        if type(response_status) is not int or not 0 <= response_status <= 7:
            raise ValueError('response_status must be an unsigned3-bit integer')
        if reset:
            return UARTResetSignals(stream_reset=True, block_messages=True)
        if self._fault:
            return UARTResetSignals(stream_reset=True, block_messages=True, fault=True)
        ready = not self._seq.block_messages and not self._seq.waiting
        start = local_request and ready
        success = rx_response and response_status == 0 and self._seq.waiting
        future = deepcopy(self._seq)
        if success:
            future.receive_response(status=0)
        future.advance_ps(self.period_ps)
        timeout = future.retries != self._seq.retries
        message = None if start or timeout else self._seq.offer()
        kind = 0 if message is None else {'noop': 1, 'request': 2, 'response': 3}[message.kind]
        pending = message is not None
        reply = kind == 3 and tx_take
        count = self._requests_seen-self._responses_sent
        overflow = rx_request and count == self.response_depth and not reply
        error = overflow or (tx_take and not pending)
        noops = 40-self._noops_sent if message is not None and kind == 1 else 0
        # Suppressing an offer must not suppress the current run-out observation.
        old_message = self._seq.offer()
        if old_message is not None and old_message.kind == 'noop':
            noops = 40-self._noops_sent
        return UARTResetSignals(
            local_ready=ready, stream_reset=self._seq.stream_disabled or start or rx_request,
            block_messages=self._seq.block_messages or start or timeout,
            tx_pending=pending, tx_word=0 if message is None else message.word, tx_kind=kind,
            waiting=self._seq.waiting, noops_left=noops, response_count=count,
            local_start=start, local_done=success and not error, retry=timeout and not error,
            reply_done=reply, fault=False, error=error)

    def tick(self, **inputs):
        out = self.observe(**inputs)
        if inputs.get('reset', False):
            self._clear()
            return out
        if self._fault:
            return out
        if out.error:
            self._clear()
            self._fault = True
            return out
        if out.local_done:
            self._seq.receive_response(status=0)
        self._seq.advance_ps(self.period_ps)
        if out.retry:
            self._noops_sent = 0
        if out.local_start:
            assert self._seq.request(all_streams=inputs.get('local_all', False))
            self._noops_sent = 0
        if out.tx_pending and inputs.get('tx_take', False):
            message = self._seq.service()
            assert message.word == out.tx_word
            if message.kind == 'noop':
                self._noops_sent += 1
            elif message.kind == 'response':
                self._responses_sent += 1
        if inputs.get('rx_request', False):
            assert self._seq.receive_request(all_streams=inputs.get('request_all', False))
            self._requests_seen += 1
        return out

    def _advance_idle(self, cycles):
        if not self._fault:
            old = self._seq.retries
            self._seq.advance_ps(cycles*self.period_ps)
            if self._seq.retries != old:
                self._noops_sent = 0

    def idle(self, cycles):
        """Compress input-free model time only when all intermediate outputs hold.

        This compresses vector storage; the RTL testbench must still execute and
        compare every real edge. Absolute-time monotonicity gives at most one
        transition without another actual Request transmission.
        """
        if type(cycles) is not int or cycles < 1:
            raise ValueError('idle cycles must be a positive integer')
        before = self.observe()
        if cycles > 1:
            first = deepcopy(self)
            first.tick()
            last = deepcopy(self)
            last._advance_idle(cycles-1)
            if first.observe() != before or last.observe() != before:
                raise ValueError('bulk idle would hide a nonfinal output transition')
        self._advance_idle(cycles)
        return before

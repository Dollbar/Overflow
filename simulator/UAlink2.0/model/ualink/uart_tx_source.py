"""Cycle reference for one fully staged stream0 UART transport source.

This model owns payload as a deque, with remaining-load and header-sent state.
It does not share RTL register indexing or arbiter selection logic. See the
source contract for external FIFO ownership, Channel4 drain and coordinated
reset requirements. Credit Update cadence and Stream Reset are separate.
"""
from collections import deque
from dataclasses import dataclass


@dataclass(frozen=True)
class UARTTxSignals:
    payload_ready: bool = False
    pending: bool = False
    word: int = 0
    word_count: int = 0
    word_index: int = 0
    busy: bool = False
    reserved_words: int = 0
    staged_words: int = 0
    tx_counter: int = 0
    latest_fc: int = 0
    done: bool = False
    error: bool = False


class UARTTxSource:
    """One reserved message, staged before becoming eligible for arbitration."""

    def __init__(self):
        self._payload = deque()
        self._reserved = 0
        self._remaining_load = 0
        self._header_sent = False
        self._tx_counter = 0
        self._latest_fc = 0

    @staticmethod
    def _bool(value, label):
        if type(value) is not bool:
            raise ValueError(f'{label} must be a boolean')

    def observe(self, *, enabled=True, take=False, reset=False):
        """Combinational outputs from current state and source service inputs."""
        for label, value in (('enabled', enabled), ('take', take), ('reset', reset)):
            self._bool(value, label)
        if reset:
            return UARTTxSignals()
        busy = self._reserved != 0
        pending = bool(enabled and busy and not self._remaining_load)
        index = self._reserved-len(self._payload)+1 if self._header_sent else 0
        word = ((self._reserved-1) << 27) | 4 if pending and not self._header_sent else 0
        if pending and self._header_sent:
            word = self._payload[0]
        return UARTTxSignals(
            payload_ready=bool(enabled and self._remaining_load), pending=pending,
            word=word, word_count=self._reserved+1 if pending else 0,
            word_index=index if pending else 0, busy=busy,
            reserved_words=self._reserved, staged_words=len(self._payload),
            tx_counter=self._tx_counter, latest_fc=self._latest_fc,
            done=bool(take and pending and self._header_sent and len(self._payload) == 1),
            error=bool((take and not pending) or (not enabled and self._header_sent)))

    def tick(self, *, enabled=True, payload_fill=0, payload_valid=False, payload_word=0,
             credit_valid=False, credit_value=0, take=False, reset=False):
        """Return pre-edge outputs, then process a single clock edge atomically."""
        for label, value in (('enabled', enabled), ('payload_valid', payload_valid),
                             ('credit_valid', credit_valid), ('take', take), ('reset', reset)):
            self._bool(value, label)
        for label, value, bits in (('payload_fill', payload_fill, 12),
                                   ('payload_word', payload_word, 32), ('credit_value', credit_value, 12)):
            if type(value) is not int or not 0 <= value < (1 << bits):
                raise ValueError(f'{label} must be an unsigned{bits}-bit integer')
        out = self.observe(enabled=enabled, take=take, reset=reset)
        if reset:
            self.__init__()
            return out
        available = (self._latest_fc-self._tx_counter) % 4096
        if credit_valid:
            self._latest_fc = credit_value
        if not self._reserved:
            if enabled and payload_fill and available:
                self._reserved = min(payload_fill, available, 32)
                self._remaining_load = self._reserved
        elif self._remaining_load:
            if out.payload_ready and payload_valid:
                self._payload.append(payload_word)
                self._remaining_load -= 1
        elif out.pending and take:
            if not self._header_sent:
                self._header_sent = True
            else:
                self._payload.popleft()
                if not self._payload:
                    self._tx_counter = (self._tx_counter+self._reserved) % 4096
                    self._reserved = 0
                    self._header_sent = False
        return out

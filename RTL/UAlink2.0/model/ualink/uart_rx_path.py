"""Stream0 UART receive framing over independent deque-based SRAM FIFO timing.

Consumes ordered uncompressed DL message DWORDs after CRC/replay validation.
Only payload enters storage. Local stream reset clears storage/credit ownership
while preserving transport run-out. This is not the reset handshake or outgoing
Credit Update scheduler. See config/uart_rx_path_contract.json for local policy.
"""
from dataclasses import dataclass

from model.ualink.receive_fifo import ReceiveFifo


@dataclass(frozen=True)
class UARTRxSignals:
    fw_valid: bool = False
    fw_word: int = 0
    rx_fill: int = 0
    initialized: bool = False
    rx_counter: int = 0
    credit_available: bool = False
    remaining: int = 0
    dropping: bool = False
    header: bool = False
    payload_write: bool = False
    payload_discard: bool = False
    done: bool = False
    credit_valid: bool = False
    credit_value: int = 0
    reset_request: bool = False
    request_all: bool = False
    reset_response: bool = False
    response_all: bool = False
    response_status: int = 0
    other_valid: bool = False
    other_word: int = 0
    error: bool = False


class UARTRxPath:
    """One receive stream; unbounded read accounting derives wire credit value."""

    def __init__(self, depth=128):
        if type(depth) is not int or not 1 <= depth <= 4095:
            raise ValueError('RX depth must be an integer in1..4095')
        self.depth = depth
        self._fifo = ReceiveFifo(depth)
        self._remaining = 0
        self._discard = False
        self._initialized = False
        self._reads = 0

    def observe(self, *, word=None, enabled=True, stream_reset=False, fw_ready=False, reset=False):
        """Observe pre-edge events without scheduling any outgoing messages."""
        for label, value in (('enabled', enabled), ('stream_reset', stream_reset),
                             ('fw_ready', fw_ready), ('reset', reset)):
            if type(value) is not bool:
                raise ValueError(label+' must be boolean')
        if word is not None and (type(word) is not int or not 0 <= word < 2**32):
            raise ValueError('word must be a32-bit integer or None')
        if reset:
            return UARTRxSignals()
        fifo = self._fifo.outputs
        active = self._initialized and not stream_reset
        dropping = bool(self._remaining and (self._discard or not active or not enabled))
        write = word is not None and bool(self._remaining) and not dropping and fifo.ready
        done = word is not None and self._remaining == 1
        head = credit = request = response = other = False
        error = bool(word is not None and self._remaining and not dropping and not fifo.ready)
        if word is not None and not self._remaining:
            message_class, message_type, stream = (word >> 2) % 16, (word >> 6) % 8, (word >> 9) % 8
            uart = message_class == 1
            head = uart and message_type == 0
            credit_kind = uart and message_type == 1 and stream == 0
            applies = stream == 0 or bool(word & 4096)
            request = uart and message_type == 6 and applies
            response = uart and message_type == 7 and applies
            credit = credit_kind and active
            other = not (head or credit_kind or request or response)
            count = (word >> 27)+1
            error = bool(head and stream == 0 and active and enabled and fifo.count+count > self.depth)
        return UARTRxSignals(
            fw_valid=bool(active and fifo.valid), fw_word=fifo.data if active and fifo.valid else 0,
            rx_fill=fifo.count if active else 0, initialized=bool(active),
            rx_counter=(self.depth+self._reads) % 4096 if active else 0,
            credit_available=bool(active and enabled), remaining=self._remaining, dropping=dropping,
            header=head, payload_write=write,
            payload_discard=bool(word is not None and self._remaining and not write), done=done,
            credit_valid=credit, credit_value=(word >> 20) if credit else 0,
            reset_request=request, request_all=bool(request and word & 4096),
            reset_response=response, response_all=bool(response and word & 4096),
            response_status=(word >> 13) % 8 if response else 0,
            other_valid=other, other_word=word if other else 0, error=error)

    def tick(self, **inputs):
        """Return current signals, then advance framing/storage/firmware ownership."""
        out = self.observe(**inputs)
        word = inputs.get('word')
        reset = inputs.get('reset', False)
        stream_reset = inputs.get('stream_reset', False)
        enabled = inputs.get('enabled', True)
        fw_ready = inputs.get('fw_ready', False)
        if reset:
            self._remaining, self._discard, self._initialized, self._reads = 0, False, False, 0
            self._fifo.step(reset=True)
            return out
        fifo_reset = stream_reset or not self._initialized
        self._fifo.step(data=word if out.payload_write else None,
                        consume=out.fw_valid and fw_ready, reset=fifo_reset)
        if stream_reset:
            self._initialized, self._reads = False, 0
        elif not self._initialized:
            self._initialized, self._reads = True, 0
        elif out.fw_valid and fw_ready:
            self._reads += 1
        if self._remaining:
            self._discard = self._discard or out.dropping or out.error
            if word is not None:
                self._remaining -= 1
                if not self._remaining:
                    self._discard = False
        elif out.header:
            self._remaining = (word >> 27)+1
            self._discard = bool(not out.initialized or not enabled or ((word >> 9) % 8) or out.error)
        return out

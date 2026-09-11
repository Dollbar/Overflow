"""DL/PL2.0 stream0 whole-message payload storage and modulo4096 credits.

Spec scope: sections2.4.4.1.1/2.4.4.1.3 and Tables2-14/2-15. This is an
event-level reference, not a cycle scheduler or a Stream Reset handshake.
Credit snapshots observe a counter; they neither schedule messages nor count
transmitted flits. In-flight reservation and header encoding are separate.
"""
from collections import deque
from dataclasses import dataclass


def _unsigned(value, bits, label):
    if type(value) is not int or not 0 <= value < (1 << bits):
        raise ValueError(f'{label} must be an unsigned {bits}-bit integer')


@dataclass(frozen=True)
class UARTTransport:
    """Owned stream0 payload, with derived header length but no encoded header."""

    payload: tuple[int, ...]

    def __post_init__(self):
        if not isinstance(self.payload, (tuple, list)) or not 1 <= len(self.payload) <= 32:
            raise ValueError('transport requires 1..32 fully staged payload DWORDs')
        payload = tuple(self.payload)
        for word in payload:
            _unsigned(word, 32, 'payload DWORD')
        object.__setattr__(self, 'payload', payload)

    @property
    def length_field(self):
        return len(self.payload)-1

    @property
    def total_word_count(self):
        return len(self.payload)+1


class UARTStreamFlowControl:
    """One end's independent TX/RX buffers and directional credit counters.

    Default capacities implement the recommended128-DWORD buffers. Other
    capacities1..4095 are bounded research configurations, not negotiated wire
    modes. Events execute in caller order; transmit/receive retire a complete
    message atomically and do not predict partial-message RTL timing.
    """

    def __init__(self, tx_depth=128, rx_depth=128):
        for label, depth in (('TX', tx_depth), ('RX', rx_depth)):
            if type(depth) is not int or not 1 <= depth <= 4095:
                raise ValueError(f'{label} depth must be an integer in1..4095')
        self._tx_depth = tx_depth
        self._rx_depth = rx_depth
        self._tx = deque()
        self._rx = deque()
        self.reset()

    def reset(self):
        """Enter local reset; this call does not perform the40-NoOp handshake."""
        self._tx.clear()
        self._rx.clear()
        self._tx_counter = 0
        self._rx_counter = 0
        self._latest_fc = 0
        self._in_reset = True
        self._channel4_enabled = False

    def release_reset(self):
        """Initialize advertised capacity once on actual local reset release."""
        if self._in_reset:
            self._rx_counter = self._rx_depth
            self._in_reset = False

    def set_channel4_enabled(self, enabled):
        if type(enabled) is not bool:
            raise ValueError('Channel4 enabled must be a boolean')
        self._channel4_enabled = enabled

    @property
    def in_reset(self):
        return self._in_reset

    @property
    def channel4_enabled(self):
        return self._channel4_enabled

    @property
    def tx_fill(self):
        return len(self._tx)

    @property
    def rx_fill(self):
        return len(self._rx)

    @property
    def tx_counter(self):
        return self._tx_counter

    @property
    def rx_counter(self):
        return self._rx_counter

    @property
    def latest_fc(self):
        return self._latest_fc

    @property
    def available_credits(self):
        return (self._latest_fc-self._tx_counter) % 4096

    def write(self, word):
        """Stage one firmware DWORD; reset discards, a full buffer rejects it."""
        _unsigned(word, 32, 'firmware DWORD')
        if self._in_reset or len(self._tx) == self._tx_depth:
            return False
        self._tx.append(word)
        return True

    def apply_credit_update(self, data_fc_seq):
        """Accept a decoded legal stream0 update; replacing the last absolute FC."""
        _unsigned(data_fc_seq, 12, 'DataFCSeq')
        if not self._in_reset:
            self._latest_fc = data_fc_seq

    def credit_snapshot(self):
        """Observe eligible RX counter; no update scheduling or flit timing."""
        if self._in_reset or not self._channel4_enabled:
            return None
        return self._rx_counter

    def next_transport_length(self):
        """Observe current admissible payload count without reserving credits."""
        if self._in_reset or not self._channel4_enabled:
            return None
        count = min(self.available_credits, len(self._tx), 32)
        return count or None

    def transmit(self):
        """Complete the next whole message; only payload charges the TX counter."""
        count = self.next_transport_length()
        if count is None:
            return None
        payload = tuple(self._tx.popleft() for _ in range(count))
        self._tx_counter = (self._tx_counter+count) % 4096
        return UARTTransport(payload)

    def receive_transport(self, message):
        """Complete a decoded transport; reject overflow before changing storage."""
        if not isinstance(message, UARTTransport):
            raise ValueError('receive requires a validated stream0 UARTTransport')
        if self._in_reset or not self._channel4_enabled:
            return False
        if len(self._rx)+len(message.payload) > self._rx_depth:
            raise BufferError('received payload exceeds available local RX storage')
        self._rx.extend(message.payload)
        return True

    def read(self):
        """Return one buffered firmware DWORD and credit only an actual read."""
        if not self._rx:
            return None
        word = self._rx.popleft()
        self._rx_counter = (self._rx_counter+1) % 4096
        return word

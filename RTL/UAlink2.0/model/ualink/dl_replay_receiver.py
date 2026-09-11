"""LLR receive ingress/sequence/enqueue event reference for DL/PL 2.0.

Sources: sections 2.6.4 and 2.6.6.1–4. Each call represents one classified
received-flit event, not a clock or Tx flit-time tick. Physical buffer admission
may instead issue discard_for_backpressure() for that event. CRC wire ordering,
buffer capacity/admission precedence and FEC-loss indications are outside this
component. Commands are returned independently of payload acceptance for the
separate Tx ACK/Replay processor; its ignore window is not implemented here.
"""
from dataclasses import dataclass, replace
from model.ualink.dl_replay_header import ReplayHeader, decode_header


@dataclass(frozen=True)
class RxState:
    last_sequence: int = 511
    bad_crc_count: int = 0
    unexpected_count: int = 0
    ambiguous: bool = False
    replay: bool = False


@dataclass(frozen=True)
class RxOutcome:
    """A candidate sequence is trusted only when accepted is true.

    request_replays=3 means assign the transmitter's remaining-request count
    to three, not append three queue entries. The transmitter captures the
    request sequence only when it actually schedules the first copy.
    """
    sequence: int | None
    accepted: bool
    deliver_payload: bool
    request_replays: int
    command: ReplayHeader | None
    reason: str


class DLReplayReceiver:
    def __init__(self, *, replay_limit: int = 50):
        self.configure_replay_limit(replay_limit)
        self.reset()

    @property
    def state(self) -> RxState:
        return self._state

    @property
    def replay_limit(self) -> int:
        return self._replay_limit

    def configure_replay_limit(self, value: int) -> None:
        """Program the 8-bit threshold; protocol actions require a later event."""
        if type(value) is not int:
            raise TypeError('replay_limit must be an integer, not a boolean')
        if not 0 <= value <= 255:
            raise ValueError('replay_limit must fit the 8-bit register')
        self._replay_limit = value

    def reset(self) -> None:
        """Reset LLR receive protocol state while preserving its configured limit."""
        self._state = RxState()

    def _unexpected_in_replay(self) -> int:
        count = min(255, self._state.unexpected_count + 1)
        request = count >= self._replay_limit
        self._state = replace(self._state, unexpected_count=0 if request else count)
        return 3 if request else 0

    def _discard(self, reason: str) -> RxOutcome:
        bad = min(7, self._state.bad_crc_count + 1)
        self._state = replace(self._state, bad_crc_count=bad,
                              ambiguous=self._state.ambiguous or bad >= 7)
        requests = self._unexpected_in_replay() if self._state.replay else 0
        return RxOutcome(None, False, False, requests, None, reason)

    def discard_for_backpressure(self) -> RxOutcome:
        """Consume a preclassified storage discard instead of calling receive.

        This does not model a FIFO or decide simultaneous error/admission
        precedence. It implements the specified state effects of that discard.
        """
        return self._discard('backpressure')

    def receive(self, word: int, *, crc_ok: bool = True) -> RxOutcome:
        """Consume an ingress flit after the caller supplies its CRC decision."""
        if type(crc_ok) is not bool:
            raise TypeError('crc_ok must be a boolean')
        header = decode_header(word)  # Validate the API before any state mutation.
        if not crc_ok or header.errors == ('reserved_op',):
            return self._discard('invalid_flit')
        if header.errors:
            # These CRC-good zero fields are explicitly dropped/logged, rather
            # than incrementing the CRC/invalid-op ambiguity counter.
            return RxOutcome(None, False, False, 0, None, header.errors[0])
        command = header if header.op in (2, 3) else None
        last = self._state.last_sequence
        if header.sequence is not None:
            sequence = header.sequence
        else:
            delta = (header.sequence_low - (last & 7)) % 8
            if header.payload and delta == 0:
                delta = 8
            sequence = (last + delta) % 512
        trusted = header.sequence is not None or (not self._state.ambiguous and not self._state.replay)
        expected = (1 if last == 511 else last + 1) if header.payload else last
        if trusted and sequence == expected:
            self._state = RxState(last_sequence=sequence)
            return RxOutcome(sequence, True, header.payload, 0, command,
                             'payload' if header.payload else 'nop')
        if trusted:
            if not self._state.replay:
                self._state = replace(self._state, replay=True, unexpected_count=0)
                requests = 3
            else:
                requests = self._unexpected_in_replay()
            reason = 'unexpected_sequence'
        elif self._state.replay:
            requests = self._unexpected_in_replay()
            reason = 'replay_command'
        else:
            # Ambiguity alone does not fabricate a replay transition absent
            # from the normative receive-enqueue rules.
            requests = 0
            reason = 'ambiguous_command'
        return RxOutcome(sequence, False, False, requests, command, reason)

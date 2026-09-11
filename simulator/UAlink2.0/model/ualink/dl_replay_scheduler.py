"""LLR source/header scheduling and two independent ingress consumers.

DL/PL 2.0 sections 2.6.6.6/.7 and Figure 2-21. Each send is one actual Flit
interval in an appropriate DL state. The caller supplies a nondecreasing FEC
codeword-group ordinal; no PHY grouping, CRC wire order, watchdog or RX FIFO is
invented here. Received accepted content is delivered directly to the caller.
"""
from dataclasses import dataclass, replace
from model.ualink.dl_replay_header import decode_header, encode_command, encode_explicit
from model.ualink.dl_replay_receiver import DLReplayReceiver, RxOutcome
from model.ualink.dl_replay_transmitter import DLReplayTransmitter, CommandResult


@dataclass(frozen=True)
class ScheduleState:
    explicit_count: int = 7
    replay_requests: int = 0
    request_sequence: int = 0
    last_request_group: int | None = None
    last_flit_group: int | None = None


@dataclass(frozen=True)
class ScheduledFlit:
    header: int
    payload: bytes | None
    sequence: int  # Diagnostic; the remote receiver must use the encoded header.
    accepted_input: bool
    replayed: bool
    first_replay: bool


@dataclass(frozen=True)
class ReceivedFlit:
    receiver: RxOutcome
    command: CommandResult
    payload: bytes | None


class DLReplayScheduler:
    def __init__(self, *, capacity: int = 255, replay_limit: int = 50):
        self.tx = DLReplayTransmitter(capacity=capacity)
        self.rx = DLReplayReceiver(replay_limit=replay_limit)
        self._state = ScheduleState()

    @property
    def state(self) -> ScheduleState:
        return self._state

    def reset(self) -> None:
        self.tx.reset()
        self.rx.reset()
        self._state = ScheduleState()

    def _receive_result(self, receiver: RxOutcome, command: CommandResult,
                        payload: bytes | None) -> ReceivedFlit:
        if receiver.request_replays:
            self._state = replace(self._state, replay_requests=3)
        return ReceivedFlit(receiver, command, payload if receiver.deliver_payload else None)

    def receive(self, word: int, *, payload: bytes | None = None,
                crc_ok: bool = True) -> ReceivedFlit:
        """Consume one ingress event and deliver its accepted opaque content.

        CRC-bad or malformed headers need not agree with the accompanying data
        presence. For CRC-good valid headers, inconsistent API metadata is an
        error detected before either consumer changes state.
        """
        if type(crc_ok) is not bool:
            raise TypeError('crc_ok must be a boolean')
        if payload is not None and type(payload) is not bytes:
            raise TypeError('payload must be immutable bytes or None')
        header = decode_header(word)
        if crc_ok and header.valid and header.payload != (payload is not None):
            raise ValueError('valid header payload flag and supplied data disagree')
        receiver = self.rx.receive(word, crc_ok=crc_ok)
        command = self.tx.receive(word, crc_ok=crc_ok)
        return self._receive_result(receiver, command, payload)

    def discard_ingress(self) -> ReceivedFlit:
        """Consume one preclassified storage discard instead of receive()."""
        receiver = self.rx.discard_for_backpressure()
        command = self.tx.discard_ingress()
        return self._receive_result(receiver, command, None)

    def send(self, *, codeword_group: int, payload: bytes | None = None) -> ScheduledFlit:
        """Transmit one Flit, reporting whether the offered normal input was used.

        Retain input externally when accepted_input is false. A full buffer
        produces a NOP unless replay supplies data. ReplaySelection captures the
        current source/first flag before the final read clears Tx replay state.
        """
        if type(codeword_group) is not int:
            raise TypeError('codeword_group must be an integer, not a boolean')
        if codeword_group < 0 or (self._state.last_flit_group is not None
                                and codeword_group < self._state.last_flit_group):
            raise ValueError('codeword_group must be nonnegative and cannot go backwards')
        if payload is not None and type(payload) is not bytes:
            raise TypeError('payload must be immutable bytes or None')
        selected = self.tx.next_replay()
        replayed = selected is not None
        first_replay = selected.first_replay if replayed else False
        entry = selected.entry if replayed else (self.tx.enqueue(payload) if payload is not None else None)
        accepted = payload is not None and entry is not None and not replayed
        sequence = entry.sequence if entry is not None else self.tx.state.last_sequence
        has_payload = entry is not None
        count = max(0, self._state.explicit_count - 1)
        pending = self._state.replay_requests
        target = self._state.request_sequence
        request_group = self._state.last_request_group
        if first_replay or count == 0:
            count = 7
            word = encode_explicit(sequence, payload=has_payload, replay=replayed)
        elif pending and codeword_group != request_group:
            if pending == 3:
                last_received = self.rx.state.last_sequence
                target = 1 if last_received == 511 else last_received + 1
            pending -= 1
            request_group = codeword_group
            word = encode_command(sequence & 7, target, payload=has_payload, request=True)
        else:
            word = encode_command(sequence & 7, self.rx.state.last_sequence, payload=has_payload)
        self._state = ScheduleState(count, pending, target, request_group, codeword_group)
        return ScheduledFlit(word, entry.payload if has_payload else None, sequence,
                             accepted, replayed, first_replay)

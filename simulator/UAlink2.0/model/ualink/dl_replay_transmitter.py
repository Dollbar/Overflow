"""Bounded LLR TxReplay contents and received ACK/Replay command reference.

DL/PL 2.0 sections 2.6.4.3/.9, 2.6.5.3–5 and 2.6.6.1–3/.5/.6.
Enqueue represents a committed normal payload transmission. NOPs do not enqueue.
Payload bytes are opaque immutable content, not a complete serialized DL Flit.
Every receive/discard_ingress call ages the replay-request ignore window once.
Flit scheduling, CRC calculation, FEC grouping and the watchdog are separate.
"""
from dataclasses import dataclass, replace
from model.ualink.dl_replay_header import decode_header


@dataclass(frozen=True)
class ReplayEntry:
    sequence: int
    payload: bytes


@dataclass(frozen=True)
class TxState:
    last_sequence: int = 511
    last_ack: int = 511
    ignore_count: int = 0
    replay: bool = False
    first_replay: bool = False


@dataclass(frozen=True)
class CommandResult:
    # Logical ACK release can leave a scheduled replay reference resident.
    acknowledged: tuple[ReplayEntry, ...]
    replay_started: bool
    reason: str


@dataclass(frozen=True)
class ReplaySelection:
    entry: ReplayEntry
    first_replay: bool


class DLReplayTransmitter:
    def __init__(self, *, capacity: int = 255):
        if type(capacity) is not int:
            raise TypeError('capacity must be an integer, not a boolean')
        if capacity < 1:
            raise ValueError('capacity must be positive')
        self._capacity = capacity
        self.reset()

    def reset(self) -> None:
        """Reset protocol/content state; preserve the implementation capacity."""
        self._state = TxState()
        self._buffer: tuple[ReplayEntry, ...] = ()
        self._scheduled: tuple[ReplayEntry, ...] = ()

    @property
    def state(self) -> TxState:
        return self._state

    @property
    def capacity(self) -> int:
        return self._capacity

    @property
    def buffer(self) -> tuple[ReplayEntry, ...]:
        """Unacknowledged payloads in their committed transmission order."""
        return self._buffer

    @property
    def scheduled(self) -> tuple[ReplayEntry, ...]:
        """Remaining replay order, including pinned content acknowledged later."""
        return self._scheduled

    @property
    def resident_count(self) -> int:
        # A schedule references existing entries; it does not copy payload data.
        return len(set(self._buffer + self._scheduled))

    @property
    def can_enqueue(self) -> bool:
        return (not self._state.replay and len(self._buffer) < 255
                and self.resident_count < self._capacity)

    def enqueue(self, payload: bytes) -> ReplayEntry | None:
        """Commit a normal payload if allowed, otherwise report backpressure.

        The caller must retain an offered payload when None is returned. This
        method does not select the mandatory outbound NOP/command on that slot.
        """
        if type(payload) is not bytes:
            raise TypeError('payload must be immutable bytes')
        if not self.can_enqueue:
            return None
        sequence = 1 if self._state.last_sequence == 511 else self._state.last_sequence + 1
        entry = ReplayEntry(sequence, payload)
        self._buffer += (entry,)
        self._state = replace(self._state, last_sequence=sequence)
        return entry

    def _age_ignore(self) -> None:
        self._state = replace(self._state, ignore_count=max(0, self._state.ignore_count - 1))

    def discard_ingress(self) -> CommandResult:
        """Count one preclassified discarded ingress instead of receive()."""
        self._age_ignore()
        return CommandResult((), False, 'discard')

    def receive(self, word: int, *, crc_ok: bool = True) -> CommandResult:
        """Process one incoming Flit independently of local payload acceptance."""
        if type(crc_ok) is not bool:
            raise TypeError('crc_ok must be a boolean')
        header = decode_header(word)  # Invalid API values must not age the state.
        self._age_ignore()
        if not crc_ok or header.errors:
            return CommandResult((), False, 'invalid_flit')
        if header.op not in (2, 3):
            return CommandResult((), False, 'no_command')
        target = header.ack_request
        last_ack = self._state.last_ack
        tail = self._state.last_sequence
        if header.op == 3:
            if self._state.ignore_count:
                return CommandResult((), False, 'request_ignored')
            if not ((target - last_ack - 1) % 511 <= 254
                    and (tail - target) % 511 <= 254):
                return CommandResult((), False, 'unexpected_request')
            start = next(i for i, entry in enumerate(self._buffer) if entry.sequence == target)
            self._scheduled = self._buffer[start:]
            self._state = replace(self._state, replay=True, first_replay=True, ignore_count=12)
            return CommandResult((), True, 'request')
        if not ((target - last_ack) % 511 <= 255 and (tail - target) % 511 <= 255):
            return CommandResult((), False, 'unexpected_ack')
        count = (target - last_ack) % 511
        released = self._buffer[:count]
        self._buffer = self._buffer[count:]
        self._state = replace(self._state, last_ack=target)
        return CommandResult(released, False, 'ack')

    def next_replay(self) -> ReplaySelection | None:
        """Commit the next scheduled replay and return its pre-update first flag.

        Later ACKs may logically release entries while this fixed replay order
        still holds their immutable references. Enqueue is blocked throughout
        replay, so the union of live and scheduled data stays within capacity.
        """
        if not self._scheduled:
            return None
        selected = ReplaySelection(self._scheduled[0], self._state.first_replay)
        self._scheduled = self._scheduled[1:]
        self._state = replace(self._state, replay=bool(self._scheduled), first_replay=False)
        return selected

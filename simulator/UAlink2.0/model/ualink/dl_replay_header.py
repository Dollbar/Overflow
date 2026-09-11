"""Logical 24-bit UALink 200G DL/PL 2.0 replay header fields.

Sources: sections 2.3.1, 2.6.2, 2.6.3 and 2.6.6.2–4, Tables 2-16/17.
No CRC decision, byte serialization, sequence reconstruction, buffering or replay
state is implied. ``valid`` only describes the header encoding. Receive-side
reserved bits are ignored; reserved operations and zero full sequence numbers
remain explicit errors for a later ingress controller to process.
"""
from dataclasses import dataclass


def _integer(value: int, lower: int, upper: int, name: str) -> int:
    if type(value) is not int:
        raise TypeError(f'{name} must be an integer, not a boolean')
    if not lower <= value <= upper:
        raise ValueError(f'{name} must be in {lower}..{upper}')
    return value


def _boolean(value: bool, name: str) -> bool:
    if type(value) is not bool:
        raise TypeError(f'{name} must be a boolean')
    return value


@dataclass(frozen=True)
class ReplayHeader:
    op: int
    payload: bool
    sequence: int | None
    sequence_low: int | None
    ack_request: int | None
    errors: tuple[str, ...]

    @property
    def valid(self) -> bool:
        """Header fields are legal; this does not imply CRC or sequence validity."""
        return not self.errors


def encode_explicit(sequence: int, *, payload: bool, replay: bool = False) -> int:
    """Encode Table 2-16 with every reserved bit zero."""
    _integer(sequence, 1, 511, 'sequence')
    _boolean(payload, 'payload')
    _boolean(replay, 'replay')
    if replay and not payload:
        raise ValueError('a NOP explicit flit cannot use the replay operation')
    return (int(replay) << 21) | (int(payload) << 20) | (sequence << 8)


def encode_command(sequence_low: int, ack_request: int, *, payload: bool,
                   request: bool = False) -> int:
    """Encode Ack or Replay Request; command low sequence zero is legal."""
    _integer(sequence_low, 0, 7, 'sequence_low')
    _integer(ack_request, 1, 511, 'ack_request')
    _boolean(payload, 'payload')
    _boolean(request, 'request')
    op = 3 if request else 2
    return (op << 21) | (int(payload) << 20) | (ack_request << 11) | (sequence_low << 8)


def decode_header(word: int) -> ReplayHeader:
    """Decode one logical header; malformed wire encodings return error reasons."""
    _integer(word, 0, 0xFFFFFF, 'header')
    op = (word >> 21) & 7
    payload = bool((word >> 20) & 1)
    if op >= 4 or (op == 1 and not payload):
        return ReplayHeader(op, payload, None, None, None, ('reserved_op',))
    if op in (0, 1):
        sequence = (word >> 8) & 511
        errors = ('zero_sequence',) if sequence == 0 else ()
        return ReplayHeader(op, payload, sequence, None, None, errors)
    ack_request = (word >> 11) & 511
    errors = ('zero_ack_request',) if ack_request == 0 else ()
    return ReplayHeader(op, payload, None, (word >> 8) & 7, ack_request, errors)

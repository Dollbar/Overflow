"""KDLink-v2 forward-flit and reverse-control codecs."""

from __future__ import annotations

from dataclasses import dataclass, replace

from collective_model.bitfields import get_bits, int_to_le_bytes, put_bits
from collective_model.crc import crc16_ccitt_false, crc32_iso_hdlc

from .constants import *


HEADER_FIELD_NAMES = (
    "version", "message_type", "opcode", "dtype", "vc", "phase", "sop", "eop", "retry",
    "src_node", "dst_node", "plane_id", "hop_limit", "link_epoch", "collective_id", "chunk_id",
    "packet_seq", "flit_seq", "payload_bytes", "reserved", "crc32",
)
REVERSE_FIELD_NAMES = (
    "version", "message_type", "vc", "plane_id", "slice_id", "phase", "link_epoch", "src_node",
    "dst_node", "collective_id", "packet_seq", "credit_delta", "credit_total", "ack_bitmap", "status",
    "reserved", "crc16",
)


def _encode_fields(owner: object, prefix: str, names: tuple[str, ...]) -> int:
    value = 0
    for name in names:
        token = name.upper()
        value = put_bits(
            value,
            getattr(owner, name),
            globals()[f"{prefix}_{token}_LSB"],
            globals()[f"{prefix}_{token}_WIDTH"],
        )
    return value


def _decode_fields(value: int, prefix: str, names: tuple[str, ...]) -> dict[str, int]:
    return {
        name: get_bits(value, globals()[f"{prefix}_{name.upper()}_LSB"], globals()[f"{prefix}_{name.upper()}_WIDTH"])
        for name in names
    }


@dataclass(frozen=True)
class KDLinkHeader:
    version: int = SCHEMA_VERSION
    message_type: int = MESSAGE_TYPE_DATA
    opcode: int = OPCODE_ALL_REDUCE
    dtype: int = DTYPE_INT32
    vc: int = VC_ROLE_COLLECTIVE
    phase: int = 0
    sop: int = 1
    eop: int = 1
    retry: int = 0
    src_node: int = 0
    dst_node: int = 1
    plane_id: int = 0
    hop_limit: int = 31
    link_epoch: int = 0
    collective_id: int = 0
    chunk_id: int = 0
    packet_seq: int = 0
    flit_seq: int = 0
    payload_bytes: int = 64
    reserved: int = 0
    crc32: int = 0

    def encode(self) -> int:
        return _encode_fields(self, "HEADER", HEADER_FIELD_NAMES)

    @classmethod
    def decode(cls, value: int) -> "KDLinkHeader":
        return cls(**_decode_fields(value, "HEADER", HEADER_FIELD_NAMES))

    def without_crc(self) -> "KDLinkHeader":
        return replace(self, crc32=0)


@dataclass(frozen=True)
class KDLinkFlit:
    header: KDLinkHeader
    payload: bytes

    def __post_init__(self) -> None:
        if len(self.payload) != PAYLOAD_WIDTH // 8:
            raise ValueError("KDLink-v2 payload must be exactly 64 bytes")
        if self.header.payload_bytes > PAYLOAD_WIDTH // 8:
            raise ValueError("payload_bytes exceeds the fixed payload")

    def crc_input(self) -> bytes:
        header96 = self.header.without_crc().encode() & ((1 << 96) - 1)
        return int_to_le_bytes(header96, 96) + self.payload[: self.header.payload_bytes]

    def with_crc(self) -> "KDLinkFlit":
        return KDLinkFlit(replace(self.header, crc32=crc32_iso_hdlc(self.crc_input())), self.payload)

    def crc_ok(self) -> bool:
        return self.header.crc32 == crc32_iso_hdlc(self.crc_input())

    def encode(self) -> int:
        return (self.header.encode() << PAYLOAD_WIDTH) | int.from_bytes(self.payload, "little")

    @classmethod
    def decode(cls, value: int) -> "KDLinkFlit":
        payload_mask = (1 << PAYLOAD_WIDTH) - 1
        payload = (value & payload_mask).to_bytes(PAYLOAD_WIDTH // 8, "little")
        return cls(KDLinkHeader.decode(value >> PAYLOAD_WIDTH), payload)

    def next_hop(self, link_epoch: int) -> "KDLinkFlit":
        if self.header.hop_limit == 0:
            raise RuntimeError("hop limit exhausted")
        header = replace(self.header, hop_limit=self.header.hop_limit - 1, link_epoch=link_epoch, crc32=0)
        return KDLinkFlit(header, self.payload).with_crc()


@dataclass(frozen=True)
class KDLinkReverseWord:
    version: int = SCHEMA_VERSION
    message_type: int = REVERSE_TYPE_ACK
    vc: int = VC_ROLE_COLLECTIVE
    plane_id: int = 0
    slice_id: int = 0
    phase: int = 0
    link_epoch: int = 0
    src_node: int = 1
    dst_node: int = 0
    collective_id: int = 0
    packet_seq: int = 0
    credit_delta: int = 0
    credit_total: int = 0
    ack_bitmap: int = 0
    status: int = 0
    reserved: int = 0
    crc16: int = 0

    def encode(self) -> int:
        return _encode_fields(self, "REVERSE", REVERSE_FIELD_NAMES)

    @classmethod
    def decode(cls, value: int) -> "KDLinkReverseWord":
        return cls(**_decode_fields(value, "REVERSE", REVERSE_FIELD_NAMES))

    def with_crc(self) -> "KDLinkReverseWord":
        raw112 = replace(self, crc16=0).encode() & ((1 << 112) - 1)
        return replace(self, crc16=crc16_ccitt_false(int_to_le_bytes(raw112, 112)))

    def crc_ok(self) -> bool:
        raw112 = replace(self, crc16=0).encode() & ((1 << 112) - 1)
        return self.crc16 == crc16_ccitt_false(int_to_le_bytes(raw112, 112))


def validate_header(header: KDLinkHeader, *, local_node: int | None = None) -> list[str]:
    errors: list[str] = []
    if header.version != SCHEMA_VERSION:
        errors.append("version")
    if header.message_type > MESSAGE_TYPE_FAULT:
        errors.append("message_type")
    if header.opcode > OPCODE_POINT_TO_POINT:
        errors.append("opcode")
    if header.src_node >= NUM_NODES or header.dst_node >= NUM_NODES:
        errors.append("node")
    if header.plane_id >= NUM_PLANES:
        errors.append("plane")
    if header.vc >= NUM_VC:
        errors.append("vc")
    if header.payload_bytes > PAYLOAD_WIDTH // 8:
        errors.append("payload_bytes")
    if header.reserved:
        errors.append("reserved")
    if local_node is not None and header.dst_node != local_node:
        errors.append("destination")
    if header.hop_limit == 0 and (local_node is None or header.dst_node != local_node):
        errors.append("hop_limit")
    if header.message_type == MESSAGE_TYPE_DATA and header.flit_seq == 0 and not header.sop:
        errors.append("sop")
    return errors

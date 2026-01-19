from dataclasses import replace

import pytest

from kdlink_model.constants import MESSAGE_TYPE_DATA, REVERSE_TYPE_ACK, VC_ROLE_COLLECTIVE
from kdlink_model.protocol import KDLinkFlit, KDLinkHeader, KDLinkReverseWord, validate_header


def sample_flit(**header_updates: int) -> KDLinkFlit:
    values = {
        "message_type": MESSAGE_TYPE_DATA,
        "opcode": 2,
        "dtype": 0,
        "vc": VC_ROLE_COLLECTIVE,
        "src_node": 3,
        "dst_node": 29,
        "plane_id": 7,
        "hop_limit": 2,
        "link_epoch": 201,
        "collective_id": 0xA35,
        "chunk_id": 0xA5B,
        "packet_seq": 0xD91,
        "flit_seq": 15,
        "payload_bytes": 64,
    }
    values.update(header_updates)
    return KDLinkFlit(KDLinkHeader(**values), bytes(range(64))).with_crc()


def test_forward_flit_round_trip_and_crc_fault() -> None:
    flit = sample_flit()
    assert KDLinkFlit.decode(flit.encode()) == flit
    assert flit.crc_ok()
    assert not KDLinkFlit.decode(flit.encode() ^ 1).crc_ok()
    assert validate_header(flit.header) == []


def test_router_rewrites_hop_local_fields_and_crc() -> None:
    original = sample_flit(hop_limit=2, link_epoch=3)
    forwarded = original.next_hop(link_epoch=4)
    assert forwarded.header.hop_limit == 1
    assert forwarded.header.link_epoch == 4
    assert forwarded.header.src_node == original.header.src_node
    assert forwarded.header.dst_node == original.header.dst_node
    assert forwarded.crc_ok()
    with pytest.raises(RuntimeError, match="hop limit"):
        sample_flit(hop_limit=0).next_hop(link_epoch=5)


def test_reverse_word_round_trip_and_crc_fault() -> None:
    word = KDLinkReverseWord(
        message_type=REVERSE_TYPE_ACK,
        vc=VC_ROLE_COLLECTIVE,
        plane_id=7,
        slice_id=1,
        link_epoch=201,
        src_node=29,
        dst_node=3,
        collective_id=0xA35,
        packet_seq=0xD91,
        credit_delta=64,
        credit_total=0xACE1,
        ack_bitmap=0xA55A,
    ).with_crc()
    assert KDLinkReverseWord.decode(word.encode()) == word
    assert word.crc_ok()
    assert not KDLinkReverseWord.decode(word.encode() ^ (1 << 77)).crc_ok()


def test_header_validation_rejects_reserved_and_wrong_destination() -> None:
    flit = sample_flit()
    assert validate_header(replace(flit.header, reserved=1), local_node=29) == ["reserved"]
    assert validate_header(flit.header, local_node=28) == ["destination"]

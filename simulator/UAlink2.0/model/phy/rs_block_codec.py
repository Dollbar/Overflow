"""UALink DL/PL2.0 RS block fields and complete transmitted Flit sequences.

Sources: sections3.2.2,3.2.4,3.2.5,3.8.2; Figure3-2 and Table3-3.
The logical sync header is separate from the 64-bit payload. Payload octet0
occupies bits7:0. This interface does not select serial header bit ordering,
RAM countdown scheduling, PCS marker overwrite, scrambling, transcoding or FEC.

Run: python3 -m unittest verification.model.test_rs_block_codec -v
Output: independent field/content checks. Next: actual parallel RS formatter RTL.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class Block:
    sync_header: int
    payload: int


def _octets(data, length):
    if type(data) is not bytes or len(data) != length:
        raise ValueError(f'expected exactly {length} bytes')


def encode_block(kind, data=b''):
    """Encode one supported RS block; data contains only its named data fields."""
    if kind == 'data':
        _octets(data, 8)
        return Block(0b01, int.from_bytes(data, 'little'))
    if kind == 'start':
        _octets(data, 7)
        payload = int.from_bytes(bytes((0x78,)) + data, 'little')
    elif kind == 'fault':
        _octets(data, 3)
        if data[:2] != bytes(2) or data[2] not in (1, 2, 3):
            raise ValueError('only local/remote fault and Link Interruption ordered sets')
        payload = int.from_bytes(bytes((0x4B,)) + data + bytes(4), 'little')
    elif kind in ('idle', 'error', 'control'):
        if kind == 'control':
            _octets(data, 8)
            codes = data
        else:
            _octets(data, 0)
            codes = bytes((0 if kind == 'idle' else 0x1E,)) * 8
        if any(code not in (0, 0x1E) for code in codes):
            raise ValueError('unsupported seven-bit control character')
        payload = 0x1E | sum(code << (8 + 7 * i) for i, code in enumerate(codes))
    elif kind == 'power_down':
        _octets(data, 0)
        payload = 0xFF
    else:
        raise ValueError('unsupported RS block kind')
    return Block(0b10, payload)


def decode_block(block):
    """Decode fields independently; reject values outside this RS coding subset.

    ValueError is a model validation result, not the PHY fault state machine.
    A start block's seven octets are preserved without guessing AM/count/PL ID.
    """
    if not isinstance(block, Block):
        raise ValueError('expected a Block record')
    if type(block.sync_header) is not int or block.sync_header not in (1, 2):
        raise ValueError('unsupported sync header')
    if type(block.payload) is not int or not 0 <= block.payload < 2**64:
        raise ValueError('payload must be an unsigned 64-bit integer')
    octets = bytes((block.payload // (256**i)) % 256 for i in range(8))
    if block.sync_header == 1:
        return 'data', octets
    block_type = octets[0]
    if block_type == 0x78:
        return 'start', octets[1:]
    if block_type == 0x4B:
        if octets[1:3] != bytes(2) or octets[3] not in (1, 2, 3) or any(octets[4:]):
            raise ValueError('reserved ordered set or corrupt O-code/zero fields')
        return 'fault', octets[1:4]
    if block_type == 0xFF:
        if any(octets[1:]):
            raise ValueError('nonzero Power Down data')
        return 'power_down', b''
    if block_type == 0x1E:
        codes = bytes((block.payload // (2 ** (8 + 7 * i))) % 128 for i in range(8))
        if any(code not in (0, 0x1E) for code in codes):
            raise ValueError('unsupported control character')
        if all(code == 0 for code in codes):
            return 'idle', b''
        if all(code == 0x1E for code in codes):
            return 'error', b''
        return 'control', codes
    raise ValueError('unsupported control block type')


def encode_data_flit(payload):
    """Map all640 DL bytes to exactly80 consecutive data blocks without delimiters."""
    _octets(payload, 640)
    return tuple(encode_block('data', payload[i:i+8]) for i in range(0, 640, 8))


def decode_data_flit(blocks):
    """Check one complete known-aligned data Flit; stream alignment is separate."""
    if not isinstance(blocks, (tuple, list)) or len(blocks) != 80:
        raise ValueError('a complete data Flit contains exactly80 blocks')
    result = bytearray()
    for block in blocks:
        kind, data = decode_block(block)
        if kind != 'data':
            raise ValueError('control block inside a complete data Flit')
        result.extend(data)
    return bytes(result)


def encode_control_flit(kind, *, marker=None, am_next_count=None,
                        link_resiliency=False, pl_id=0):
    """Format a caller-selected control Flit, without choosing transmission policy.

    RAM None count means no AM has been scheduled (0xFF). Explicit count bytes
    are formatted unchanged; this function does not resolve RSP01 scheduling.
    Power Down Start always carries PL ID in its last block per section3.2.4.8.
    """
    if kind not in ('idle', 'local_fault', 'remote_fault', 'power_down'):
        raise ValueError('unsupported transmitted control Flit')
    if marker not in (None, 'am', 'ram') or (kind == 'power_down' and marker == 'ram'):
        raise ValueError('unsupported control/marker combination')
    if type(link_resiliency) is not bool or type(pl_id) is not int or pl_id not in (0, 1):
        raise ValueError('explicit resiliency boolean and PL ID0/1 required')
    if am_next_count is not None:
        if marker != 'ram' or type(am_next_count) is not int or not 0 <= am_next_count <= 255:
            raise ValueError('count is an unsigned byte used only for RAM')
    if kind in ('local_fault', 'remote_fault'):
        code = 1 if kind == 'local_fault' else 2
        base = encode_block('fault', bytes((0, 0, code)))
    else:
        base = encode_block(kind)
    blocks = [base] * 80
    if marker is not None:
        count = 0 if marker == 'am' else 255 if am_next_count is None else am_next_count
        blocks[0] = encode_block('start', bytes((count,)) * 7)
        for i in range(1, 8):
            blocks[i] = encode_block('start', bytes(7))
        if link_resiliency or kind == 'power_down':
            blocks[79] = encode_block('start', bytes(6) + bytes((pl_id,)))
    return tuple(blocks)

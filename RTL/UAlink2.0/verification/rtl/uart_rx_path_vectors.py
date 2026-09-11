"""Generate independent UART receive cycle vectors and expected event counts.

Run: python3 verification/rtl/uart_rx_path_vectors.py --depth 128 --seed 17
     --cycles 20000 --output vectors.mem --summary vectors.json
Outputs:37-bit inputs and complete pre/post output buses; next: real SRAM RTL.
"""
import argparse
import json
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.uart_rx_path import UARTRxPath

FIELDS = (('fw_valid', 1), ('fw_word', 32), ('rx_fill', 12), ('initialized', 1),
          ('rx_counter', 12), ('credit_available', 1), ('remaining', 6), ('dropping', 1),
          ('header', 1), ('payload_write', 1), ('payload_discard', 1), ('done', 1),
          ('credit_valid', 1), ('credit_value', 12), ('reset_request', 1), ('request_all', 1),
          ('reset_response', 1), ('response_all', 1), ('response_status', 3),
          ('other_valid', 1), ('other_word', 32), ('error', 1))
OUTPUT_BITS = sum(width for _, width in FIELDS)


def pack(items):
    result = 0
    for value, width in items:
        assert 0 <= int(value) < 2**width
        result = (result << width) | int(value)
    return result


def generate(depth, seed, cycles):
    rng, end = random.Random(seed), UARTRxPath(depth)
    rows = []
    stats = dict.fromkeys(('rows', 'payload_writes', 'reads', 'messages', 'headers', 'discards',
                          'errors', 'credits', 'requests', 'responses', 'others', 'resets',
                          'stream_resets', 'read_counter_wraps', 'max_rx_fill'), 0)

    def emit(**kwargs):
        reset = kwargs.get('reset', False)
        stream_reset = kwargs.get('stream_reset', False)
        enabled = kwargs.get('enabled', True)
        ready = kwargs.get('fw_ready', False)
        word = kwargs.get('word')
        inputs = pack(((not reset, 1), (stream_reset, 1), (enabled, 1),
                       (word is not None, 1), (word or 0, 32), (ready, 1)))
        before = end.tick(**kwargs)
        after = end.observe(**kwargs)
        values = [pack((getattr(out, n), w) for n, w in FIELDS) for out in (before, after)]
        digits = (OUTPUT_BITS+3)//4
        rows.append(f'{inputs:010x} {values[0]:0{digits}x} {values[1]:0{digits}x}\n')
        stats['rows'] += 1
        for key, field in (('payload_writes', 'payload_write'), ('messages', 'done'),
                           ('headers', 'header'), ('discards', 'payload_discard'), ('errors', 'error'),
                           ('credits', 'credit_valid'), ('requests', 'reset_request'),
                           ('responses', 'reset_response'), ('others', 'other_valid')):
            stats[key] += int(getattr(before, field))
        stats['reads'] += int(before.fw_valid and ready)
        stats['resets'] += int(reset)
        stats['stream_resets'] += int(stream_reset and not reset)
        stats['read_counter_wraps'] += int(before.fw_valid and ready and before.rx_counter == 4095 and after.rx_counter == 0)
        stats['max_rx_fill'] = max(stats['max_rx_fill'], after.rx_fill)
        return before

    def drain(**kwargs):
        for _ in range(depth+8):
            emit(fw_ready=True, **kwargs)
            if not end.observe(**kwargs).rx_fill:
                break
        assert end.observe(**kwargs).rx_fill == 0

    def transport(payload, **kwargs):
        emit(word=((len(payload)-1) << 27) | 4, **kwargs)
        for word in payload:
            emit(word=word, **kwargs)

    emit(reset=True)
    emit()
    # Fill the precise configured capacity; neither headers nor physical padding count.
    serial = 0
    while serial < depth:
        payload = list(range(serial, min(serial+32, depth)))
        transport(payload)
        serial += len(payload)
    assert end.observe().rx_fill == depth
    transport([0xBAD0, 0xBAD1])
    # A read on the header edge still cannot rescue this full-queue admission.
    emit(word=4, fw_ready=True)
    emit(word=0xBAD2)
    drain()
    for length in range(1, 33):
        emit(word=((length-1) << 27) | 0x7FFF003 | 4)
        for index in range(length):
            if index % 3 == 0:
                emit(fw_ready=True)
            emit(word=(4, 0x44, 0x184, 0x1C4, 0, 0xFFFFFFFF)[index % 6], fw_ready=bool(index % 2))
        drain()
    # Preserve framing even when stream reset/disable happens on an empty ingress cycle.
    for local_reset in (False, True):
        emit(word=(3 << 27) | 4)
        emit(word=0xCAFE)
        emit(stream_reset=local_reset, enabled=local_reset)
        emit()
        for word in (0x184, 0x1C4, 0x44):
            emit(word=word)
        drain(enabled=False)
    for stream in range(1, 8):
        emit(word=(1 << 27) | (stream << 9) | 4)
        emit(word=0x44)
        emit(word=0x184)
    for word in (0, 0x40, 0x120, 0x84, 0x244, 0xFFFFFFFF):
        emit(word=word)
    for value in (0, 1, 128, 4095):
        emit(word=(value << 20) | 0xFF047, enabled=False)
    emit(word=0x184, stream_reset=True)
    emit(word=0x1F84, stream_reset=True)
    for status in range(8):
        emit(word=(status << 13) | 0x1C4, stream_reset=True)
    emit(word=0x44, stream_reset=True)
    emit()
    # Two actual read-counter wraps without reset, including very shallow storage.
    delivered = 0
    while delivered < 8256:
        count = min(depth, 32, 8256-delivered)
        transport([0x40000000+delivered+i for i in range(count)], fw_ready=True)
        drain()
        delivered += count
    assert stats['read_counter_wraps'] >= 2
    pending = []
    for _ in range(cycles):
        global_reset = rng.randrange(500) == 0
        local_reset = rng.randrange(125) == 0
        enabled = rng.randrange(20) != 0
        if global_reset:
            pending.clear()
        word = None
        if not global_reset and rng.randrange(4) != 0:
            if pending:
                word = pending.pop(0)
            elif rng.randrange(3):
                count = rng.randint(1, 32)
                stream = rng.randrange(8) if rng.randrange(25) == 0 else 0
                word = ((count-1) << 27) | (stream << 9) | 4
                pending = [rng.choice((rng.getrandbits(32), 4, 0x44, 0x184, 0x1C4)) for _ in range(count)]
            else:
                word = rng.choice((0, 0x40, 0x120, 0x184, 0x1C4, (rng.randrange(4096) << 20) | 0x44))
        emit(word=word, reset=global_reset, stream_reset=local_reset, enabled=enabled,
             fw_ready=rng.randrange(3) != 0)
    for word in pending:
        emit(word=word, fw_ready=True)
    assert end.observe().remaining == 0
    drain()
    assert stats['max_rx_fill'] == depth
    assert stats['reads'] >= 8256 and stats['discards'] > 0 and stats['errors'] > 0
    return rows, dict(stats, depth=depth, seed=seed, random_cycles=cycles, output_bits=OUTPUT_BITS,
                      final_fill=0, final_remaining=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--depth', type=int, default=128)
    parser.add_argument('--seed', type=int, default=17)
    parser.add_argument('--cycles', type=int, default=20000)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--summary', type=Path, required=True)
    args = parser.parse_args()
    if args.cycles < 0:
        parser.error('cycles must be nonnegative')
    rows, summary = generate(args.depth, args.seed, args.cycles)
    args.output.write_text(''.join(rows))
    args.summary.write_text(json.dumps(summary, indent=2)+'\n')


if __name__ == '__main__':
    main()

"""Compose public FIFO/source/arbiter models for actual SRAM-path simulation.

Run: python3 verification/rtl/uart_tx_path_vectors.py --depth 128 --seed 17
     --cycles 20000 --output vectors.mem --summary vectors.json.
Outputs:379-bit inputs,124-bit pre-edge outputs and58-bit post-edge state.
Next: compare the real wrapper and authorized SRAM models; no free RAM data.
"""
import argparse
from pathlib import Path
import json
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.receive_fifo import ReceiveFifo
from model.ualink.uart_tx_source import UARTTxSource
from model.ualink.dl_message_scheduler import DLMessageArbiter, Message

OTHERS = ((0, 0), (0, 1), (0, 4), (0, 5), (0, 6), (8, 0), (8, 4), (1, 1), (1, 6), (1, 7))
CATALOG = OTHERS[:7]+((1, 0),)+OTHERS[7:]


def pack(items):
    value = 0
    for item, width in items:
        assert 0 <= int(item) < (1 << width)
        value = (value << width) | int(item)
    return value


def generate(depth, seed, cycles):
    fifo, source, arbiter = ReceiveFifo(depth), UARTTxSource(), DLMessageArbiter(queue_depth=1)
    rng = random.Random(seed)
    pending = {}
    staged = []
    uart_queued = False
    uart_active, uart_index = False, 0
    rows = []
    stats = dict.fromkeys(('rows', 'writes', 'payloads', 'uart_messages', 'other_messages', 'resets',
                           'full_rejections', 'reset_while_busy', 'counter_wraps', 'max_buffered'), 0)
    served_sources = set()
    serial = 0

    def offer(index):
        nonlocal serial
        if index in pending:
            return
        kind = OTHERS[index]
        word = (0x20000000 | (serial << 9) | (kind[0] << 2) | (kind[1] << 6)) & 0xFFFFFFFF
        serial += 1
        message = Message(kind, (word,))
        assert arbiter.offer(message)
        pending[index] = message

    def emit(*, reset=False, enabled=True, data=None, credit=False, segment=True):
        nonlocal uart_queued, uart_active, uart_index
        f = fifo.outputs
        old = source.observe()
        s = source.observe(enabled=enabled, reset=reset)
        total = f.count+s.staged_words if not reset else 0
        ready = not reset and f.ready and total < depth
        bits = sum(1 << index for index in pending)
        words = sum(message.words[0] << (32*index) for index, message in pending.items())
        fc = (old.tx_counter+128) % 4096
        inputs = pack([(not reset, 1), (enabled, 1), (data is not None, 1), (data or 0, 32),
                       (credit, 1), (fc, 12), (segment, 1), (bits, 10), (words, 320)])
        if not reset and s.pending and not uart_queued:
            assert len(staged) == s.reserved_words
            assert arbiter.offer(Message((1, 0), (s.word, *staged)))
            uart_queued = True
        before_locked, before_index = uart_active, uart_index
        beat = arbiter.tick(segment_available=segment, reset=reset)
        uart_take = beat is not None and beat.source == (1, 0)
        other_take = 0
        if beat and not uart_take:
            index = OTHERS.index(beat.source)
            assert pending[index].words[0] == beat.word and beat.last
            other_take = 1 << index
            del pending[index]
        out = source.tick(enabled=enabled, payload_fill=f.count, payload_valid=f.valid,
                          payload_word=f.data, credit_valid=credit, credit_value=fc,
                          take=uart_take, reset=reset)
        step = fifo.step(data if ready else None, consume=out.payload_ready, reset=reset)
        if step.consumed is not None:
            staged.append(step.consumed)
        if uart_take:
            assert (out.word, out.word_index, out.done) == (beat.word, beat.index, beat.last)
            uart_active, uart_index = not beat.last, 0 if beat.last else beat.index+1
            if beat.last:
                uart_queued = False
                staged.clear()
        if reset:
            pending.clear()
            staged.clear()
            uart_queued, uart_active, uart_index = False, False, 0
        assert not out.error
        outputs = pack([(ready, 1), (total, 13), (out.tx_counter, 12), (out.busy, 1),
                        (out.reserved_words, 6), (out.staged_words, 6), (out.latest_fc, 12),
                        (beat is not None, 1), (beat.word if beat else 0, 32),
                        (CATALOG.index(beat.source) if beat else 0, 4), (beat.index if beat else 0, 6),
                        (beat.last if beat else False, 1), (other_take, 10), (other_take, 10),
                        (out.done, 1), (before_locked and not reset, 1), (False, 1),
                        (before_index if not reset else 0, 6)])
        after = source.observe(enabled=enabled, reset=reset)
        f_after = fifo.outputs
        total_after = f_after.count+after.staged_words if not reset else 0
        post = pack([(not reset and f_after.ready and total_after < depth, 1), (total_after, 13),
                     (after.tx_counter, 12), (after.busy, 1), (after.reserved_words, 6),
                     (after.staged_words, 6), (after.latest_fc, 12), (uart_active, 1), (uart_index, 6)])
        rows.append(f'{inputs:095x} {outputs:031x} {post:015x}\n')
        stats['rows'] += 1
        stats['writes'] += int(step.accepted)
        stats['payloads'] += int(uart_take and beat.index > 0)
        stats['uart_messages'] += int(out.done)
        stats['other_messages'] += int(bool(other_take))
        stats['resets'] += int(reset)
        stats['full_rejections'] += int(data is not None and not reset and not ready)
        stats['reset_while_busy'] += int(reset and old.busy)
        stats['counter_wraps'] += int(out.done and after.tx_counter < out.tx_counter)
        stats['max_buffered'] = max(stats['max_buffered'], total_after)
        if beat:
            served_sources.add(CATALOG.index(beat.source))
        assert total_after <= depth
        return step.accepted

    emit(reset=True)
    # Offline firmware preload must reach exactly the configured total capacity.
    for word in range(depth):
        assert emit(enabled=False, data=0x10000000+word, credit=True)
    for _ in range(4):
        assert not emit(enabled=False, data=0xDEADBEEF)
    for index in range(10):
        offer(index)
    waiting_word = 0xDEADBEEF
    for _ in range(depth*5+200):
        if emit(data=waiting_word, credit=True, segment=True):
            waiting_word = None
        if waiting_word is None and not source.observe().busy and fifo.outputs.count == 0 and arbiter.pending() == 0:
            break
    assert waiting_word is None
    # Cross modulo4096 through actual message completions without intervening reset.
    wrap_words = 0
    for _ in range(5120*10+depth*5):
        if emit(data=0x40000000+wrap_words if wrap_words < 5120 else None, credit=True):
            wrap_words += 1
        if wrap_words == 5120 and not source.observe().busy and fifo.outputs.count == 0:
            break
    assert wrap_words == 5120 and stats['counter_wraps'] >= 1
    producer_word = None
    next_word = 0x80000000
    for _ in range(cycles):
        if rng.random() < 0.0015:
            emit(reset=True)
            producer_word = None
            continue
        for index in range(10):
            if rng.random() < 0.025:
                offer(index)
        if producer_word is None and rng.random() < 0.68:
            producer_word = next_word
            next_word += 1
        if emit(data=producer_word, credit=rng.random() < 0.12, segment=rng.random() < 0.78):
            producer_word = None
    for _ in range(depth*12+500):
        if emit(data=producer_word, credit=True):
            producer_word = None
        if producer_word is None and not source.observe().busy and fifo.outputs.count == 0 and arbiter.pending() == 0:
            break
    assert producer_word is None
    assert fifo.outputs.count == source.observe().staged_words == 0 and not source.observe().busy
    assert arbiter.pending() == 0 and not uart_active
    emit()
    assert served_sources == set(range(11)) and stats['max_buffered'] == depth
    stats.update(depth=depth, seed=seed, random_cycles=cycles, input_bits=379,
                 output_bits=124, post_state_bits=58, served_sources=sorted(served_sources))
    return rows, stats


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--depth', type=int, default=128)
    p.add_argument('--seed', type=int, default=17)
    p.add_argument('--cycles', type=int, default=20000)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--summary', type=Path, required=True)
    args = p.parse_args()
    if not 1 <= args.depth <= 4095 or args.cycles < 0:
        p.error('depth1..4095 and nonnegative cycles required')
    rows, stats = generate(args.depth, args.seed, args.cycles)
    args.output.write_text(''.join(rows))
    args.summary.write_text(json.dumps(stats, indent=2)+'\n')


if __name__ == '__main__':
    main()

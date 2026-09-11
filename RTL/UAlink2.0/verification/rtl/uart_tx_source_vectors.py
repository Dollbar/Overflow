"""Independent cycle-model vectors for full UART TX source outputs and state.

Run: python3 verification/rtl/uart_tx_source_vectors.py --output vectors.mem
     --summary vectors.json [--seed 17 --cycles 4000]
Outputs:61-bit inputs,85-bit pre-edge outputs,85-bit post-edge outputs.
Next: run the real RTL testbench against these retained vectors.
"""
import argparse
from collections import deque
import json
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.uart_tx_source import UARTTxSource


def packed(values):
    result = 0
    for value, width in values:
        assert 0 <= int(value) < (1 << width)
        result = (result << width) | int(value)
    return result


def observation(out):
    widths = (1, 1, 32, 6, 6, 1, 6, 6, 12, 12, 1, 1)
    return packed(zip(vars(out).values(), widths))


def generate(seed, cycles):
    rng = random.Random(seed)
    source = UARTTxSource()
    rows = []
    counts = dict.fromkeys(('rows', 'loads', 'words', 'messages', 'errors', 'resets',
                            'reset_while_busy', 'disabled_active', 'staging_stalls',
                            'arbiter_stalls', 'counter_wraps'), 0)
    lengths = set()

    def emit(**overrides):
        args = dict(enabled=True, payload_fill=0, payload_valid=False, payload_word=0,
                    credit_valid=False, credit_value=0, take=False, reset=False)
        args.update(overrides)
        before = source.observe()
        out = source.tick(**args)
        after = source.observe(enabled=args['enabled'], take=args['take'], reset=args['reset'])
        stimulus = packed([(not args['reset'], 1), (args['enabled'], 1), (args['payload_fill'], 12),
                           (args['payload_valid'], 1), (args['payload_word'], 32),
                           (args['credit_valid'], 1), (args['credit_value'], 12), (args['take'], 1)])
        rows.append(f'{stimulus:016x} {observation(out):022x} {observation(after):022x}\n')
        counts['rows'] += 1
        for key, event in (('loads', out.payload_ready and args['payload_valid']),
                           ('words', out.pending and args['take']), ('messages', out.done),
                           ('errors', out.error), ('resets', args['reset']),
                           ('reset_while_busy', args['reset'] and before.busy),
                           ('disabled_active', not args['enabled'] and before.word_index > 0),
                           ('staging_stalls', out.payload_ready and not args['payload_valid']),
                           ('arbiter_stalls', out.pending and not args['take']),
                           ('counter_wraps', out.done and after.tx_counter < out.tx_counter)):
            counts[key] += int(event)
        if not out.busy and after.busy:
            lengths.add(after.reserved_words)
        return out

    def message(words, delayed=True):
        count = len(words)
        fc = (source.observe().tx_counter+count) % 4096
        emit(credit_valid=True, credit_value=fc)
        emit(payload_fill=count)
        for index, word in enumerate(words):
            if delayed and index % 3 == 0:
                emit(payload_fill=count-index)
            emit(payload_valid=True, payload_word=word, payload_fill=count-index)
        for index in range(count+1):
            if delayed and index % 4 == 0:
                emit(payload_fill=4095)
            emit(take=True, payload_fill=4095)

    emit(reset=True)
    emit(take=True)
    for count in range(1, 33):
        message([0x10000000+count*64+index for index in range(count)])
    # Reach4095 through real completed payloads, then cross wrap with two words.
    emit(reset=True)
    sent = 0
    while sent < 4095:
        count = min(32, 4095-sent)
        message(list(range(sent, sent+count)), delayed=False)
        sent += count
    message([4095, 4096])
    # Preserve staging and service ownership through offline and invalid take.
    emit(credit_valid=True, credit_value=10)
    emit(payload_fill=3)
    emit(payload_valid=True, payload_word=0xABC0, take=True)
    emit(enabled=False, payload_valid=True, payload_word=0xBAD0)
    emit(payload_valid=True, payload_word=0xABC1)
    emit(payload_valid=True, payload_word=0xABC2)
    emit(enabled=False, take=True)
    emit(take=True)
    emit(enabled=False)
    emit(enabled=False, take=True, credit_valid=True, credit_value=50)
    emit(take=True)
    emit(take=True)
    emit(take=True)
    # Explicit aborts at every header/payload boundary and during partial load.
    for take_count in range(5):
        emit(reset=True)
        emit(credit_valid=True, credit_value=4)
        emit(payload_fill=4)
        for word in range(4):
            emit(payload_valid=True, payload_word=0x80000000+word)
        for _ in range(take_count):
            emit(take=True)
        emit(reset=True, take=True)
    emit(credit_valid=True, credit_value=4)
    emit(payload_fill=4)
    emit(payload_valid=True, payload_word=99)
    emit(reset=True)
    fifo = deque()
    next_word = 0x40000000
    credit_sequence = 0
    for _ in range(cycles):
        if rng.random() < 0.006:
            emit(reset=True)
            fifo.clear()
            credit_sequence = 0
            continue
        for _ in range(rng.randrange(4)):
            if len(fifo)+source.observe().staged_words < 128:
                fifo.append(next_word)
                next_word += 1
        enabled = rng.random() >= 0.06
        valid = bool(fifo) and rng.random() < 0.78
        credit_valid = rng.random() < 0.09
        if credit_valid:
            credit_sequence = (credit_sequence+rng.randrange(1, 65)) % 4096
        view = source.observe(enabled=enabled)
        take = (view.pending and rng.random() < 0.72) or rng.random() < 0.012
        out = emit(enabled=enabled, payload_fill=len(fifo), payload_valid=valid,
                   payload_word=fifo[0] if fifo else rng.getrandbits(32),
                   credit_valid=credit_valid, credit_value=credit_sequence, take=take)
        if out.payload_ready and valid:
            fifo.popleft()
    emit(reset=True)
    emit()
    counts.update(seed=seed, random_cycles=cycles, reservation_lengths=sorted(lengths),
                  input_bits=61, output_bits=85, post_output_bits=85,
                  random_fifo_capacity_including_staging=128)
    assert counts['counter_wraps'] >= 1 and sorted(lengths) == list(range(1, 33))
    return rows, counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--summary', type=Path, required=True)
    parser.add_argument('--seed', type=int, default=17)
    parser.add_argument('--cycles', type=int, default=4000)
    args = parser.parse_args()
    if args.cycles < 0:
        parser.error('cycles must not be negative')
    rows, counts = generate(args.seed, args.cycles)
    args.output.write_text(''.join(rows))
    args.summary.write_text(json.dumps(counts, indent=2)+'\n')


if __name__ == '__main__':
    main()

"""Independent DL message arbitration vectors, using only public model methods.

Run: python3 verification/rtl/dl_message_vectors.py --output vectors.mem
     --summary vectors.json --seed 17 --cycles 4000
Outputs: packed pre-edge inputs/events and post-edge ownership observations.
Next: run these vectors against the RTL with run_dl_message_arbiter.py.
"""

import argparse
from collections import Counter, deque
import json
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.dl_message_scheduler import DLMessageArbiter, Message


# Literal protocol catalog, separate from the model's private selection tables.
SOURCES = ((0, 0), (0, 1), (0, 4), (0, 5), (0, 6), (8, 0),
           (8, 4), (1, 0), (1, 1), (1, 6), (1, 7))


def pack(*fields):
    value = 0
    for width, part in fields:
        assert 0 <= part < (1 << width), (width, part)
        value = (value << width) | part
    return value


class Vectors:
    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.model = DLMessageArbiter(queue_depth=2)
        self.queues = [deque() for _ in SOURCES]
        self.uart_index = 0
        self.rows = []
        self.counts = Counter()
        self.sources = Counter()
        self.lengths = set()
        self.serial = 0

    def offer(self, source, length=None):
        if length is None:
            length = self.rng.randint(2, 33) if source == 7 else 1
        self.serial += 1
        # Tags and random DWORDs are distinct from any future wire encoder.
        words = tuple(self.rng.getrandbits(32) for _ in range(length))
        message = Message(SOURCES[source], words, str(self.serial))
        accepted = self.model.offer(message)
        assert accepted == (len(self.queues[source]) < 2)
        if accepted:
            self.queues[source].append(message)
        else:
            self.counts['rejected_offers'] += 1

    def step(self, *, segment=True, reset=False, drop_uart=False,
             length_override=None):
        before_index = self.uart_index
        locked = before_index != 0
        pending = sum(bool(queue) << n for n, queue in enumerate(self.queues))
        words = 0
        for n, queue in enumerate(self.queues):
            if queue:
                index = before_index if n == 7 else 0
                words |= queue[0].words[index] << (32*n)
        length = len(self.queues[7][0].words) if self.queues[7] else 0
        if length_override is not None:
            assert locked, 'length may change after capture, not before admission'
            length = length_override
        if drop_uart:
            assert locked
            pending &= ~(1 << 7)
        stimulus = pack((1, int(not reset)), (1, int(segment)),
                        (11, pending), (352, words), (6, length))
        # A fault with a locked owner has no service, even for pending rivals.
        beat = self.model.tick(segment_available=segment and not drop_uart,
                               reset=reset)
        valid = beat is not None
        source = SOURCES.index(beat.source) if beat else 0
        take = 1 << source if beat else 0
        done = take if beat and beat.last else 0
        error = int(drop_uart and not reset)
        expected = pack((1, int(valid)), (32, beat.word if beat else 0),
                        (4, source), (6, beat.index if beat else 0),
                        (1, int(beat.last) if beat else 0), (11, take),
                        (11, done), (1, error),
                        (1, int(locked and not reset)),
                        (6, before_index if not reset else 0))
        if reset:
            for queue in self.queues:
                queue.clear()
            self.uart_index = 0
            self.counts['resets'] += 1
            self.counts['reset_while_locked'] += int(locked)
        elif beat:
            message = self.queues[source][0]
            assert message.tag == beat.tag
            assert message.words[beat.index] == beat.word
            assert beat.last == (beat.index == len(message.words)-1)
            if source == 7:
                if beat.index == 0:
                    self.lengths.add(len(message.words))
                self.uart_index = 0 if beat.last else beat.index+1
            if beat.last:
                self.queues[source].popleft()
                self.counts['messages'] += 1
                self.sources[str(source)] += 1
            self.counts['words'] += 1
        self.counts['errors'] += error
        self.counts['stalls'] += int(not segment and not reset)
        self.counts['withdrawn_owner'] += int(drop_uart and not reset)
        self.counts['length_changed_while_locked'] += int(length_override is not None)
        after = pack((1, int(self.uart_index != 0)), (6, self.uart_index))
        self.rows.append((stimulus, expected, after))
        assert self.model.pending() == sum(map(len, self.queues))

    def invalid_length(self, length):
        self.step(reset=True)
        # Independent literal fault vector: malformed UART does not block Basic.
        pending = (1 << 7) | 1
        stimulus = pack((1, 1), (1, 1), (11, pending),
                        (352, 0x13579bdf | (0x2468ace0 << (7*32))), (6, length))
        expected = pack((1, 1), (32, 0x13579bdf), (4, 0), (6, 0),
                        (1, 1), (11, 1), (11, 1), (1, 1), (1, 0), (6, 0))
        self.rows.append((stimulus, expected, 0))
        self.counts['words'] += 1
        self.counts['messages'] += 1
        self.counts['errors'] += 1
        self.counts['invalid_lengths'] += 1
        self.sources['0'] += 1
        # Reset resynchronizes the functional model after the explicit fault row.
        self.step(reset=True)

    def generate(self, cycles):
        self.step(reset=True)
        self.step()
        # All source types and every possible UART length, amid eager rivals.
        for length in range(2, 34):
            self.step(reset=True)
            for source in range(11):
                self.offer(source, length if source == 7 else 1)
            while self.model.pending():
                self.step()
        # Check captured length, ownership containment, stalls and reset in flight.
        self.step(reset=True)
        self.offer(7, 33)
        self.step()
        for source in (0, 5, 8, 9, 10):
            self.offer(source)
        self.step(drop_uart=True)
        self.step(segment=False, length_override=2)
        self.step(length_override=2)
        self.step(length_override=63)
        self.step(reset=True)
        for length in (0, 1, 34, 63):
            self.invalid_length(length)
        # Continuously pending groups exercise both round-robin levels.
        for _ in range(700):
            for source in range(11):
                if len(self.queues[source]) < 2:
                    self.offer(source, 2 if source == 7 else 1)
            self.step()
        self.step(reset=True)
        # Seeded arrivals, full-queue rejection, changing captured lengths/stalls.
        for _ in range(cycles):
            for source in range(11):
                if self.rng.random() < 0.10:
                    self.offer(source)
            self.step(segment=self.rng.random() >= 0.22,
                      reset=self.rng.random() < 0.008,
                      length_override=(self.rng.randrange(64)
                                       if self.uart_index else None))
        while self.model.pending():
            self.step()
        self.step()
        assert self.lengths == set(range(2, 34))
        assert set(self.sources) == set(map(str, range(11)))
        return {'rows': len(self.rows), **dict(self.counts),
                'messages_by_source': dict(self.sources),
                'uart_lengths': sorted(self.lengths),
                'input_bits': 371, 'event_bits': 74, 'state_bits': 7}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--summary', type=Path, required=True)
    parser.add_argument('--seed', type=int, default=17)
    parser.add_argument('--cycles', type=int, default=4000)
    args = parser.parse_args()
    if args.cycles < 1000:
        parser.error('cycles must be at least 1000 to retain randomized traffic')
    vectors = Vectors(args.seed)
    summary = vectors.generate(args.cycles)
    summary.update(seed=args.seed, random_cycles=args.cycles)
    args.output.write_text(''.join(f'{a:093x} {b:019x} {c:02x}\n'
                                   for a, b, c in vectors.rows))
    args.summary.write_text(json.dumps(summary, indent=2)+'\n')


if __name__ == '__main__':
    main()

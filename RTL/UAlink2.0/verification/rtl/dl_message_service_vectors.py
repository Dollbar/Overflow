"""Expand independent service-bound witnesses into complete arbiter port vectors.
Run: python3 verification/rtl/dl_message_service_vectors.py --output FILE --summary FILE --gap 1
Outputs: pre-edge inputs, all 74 public output bits and post-edge ownership;
         case boundaries and exact service-opportunity counts.
Next: run the unchanged grant arbiter with the companion self-checking testbench.
"""
import argparse
from dataclasses import asdict
import itertools
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.dl_message_service import service_bound, locked_service_bound, reset_prefix


def pack(*fields):
    result = 0
    for width, value in fields:
        if type(value) is not int or not 0 <= value < 1 << width:
            raise ValueError('vector field outside width')
        result = (result << width) | value
    return result


class Writer:
    def __init__(self, output, gap):
        if type(gap) is not int or gap < 1:
            raise ValueError('gap must be a positive integer')
        self.output, self.gap = output, gap
        self.rows = self.words = self.messages = self.stalls = self.index = 0

    def row(self, pending, source, index, last, available=True, reset=False):
        words = tuple(((self.rows * 0x10101) ^ (n * 0x9137951) ^ (index * 0x13579) ^ 0xB7654321) & 0xFFFFFFFF for n in range(11))
        stimulus = pack((1, int(not reset)), (1, int(available)), (11, pending),
                        (352, sum(word << (n * 32) for n, word in enumerate(words))), (6, 33))
        valid = available and not reset
        take = (1 << source) if valid else 0
        owned = self.index != 0 and not reset
        expected = pack((1, int(valid)), (32, words[source] if valid else 0),
                        (4, source if valid else 0), (6, index if valid else 0),
                        (1, int(last and valid)), (11, take), (11, take if last else 0),
                        (1, 0), (1, int(owned)), (6, self.index if owned else 0))
        if reset:
            self.index = 0
        elif valid and source == 7:
            self.index = 0 if last else index + 1
        after = (int(self.index != 0) << 6) | self.index
        self.output.write(f'{stimulus:093x} {expected:019x} {after:02x}\n')
        self.rows += 1
        self.words += int(valid)
        self.messages += int(last and valid)
        self.stalls += int(not available and not reset)

    def beat(self, pending, source, index, last):
        for _ in range(self.gap - 1):
            self.row(pending, source, index, last, available=False)
        self.row(pending, source, index, last)

    def message(self, pending, source):
        length = 33 if source == 7 else 1
        for index in range(length):
            self.beat(pending, source, index, index == length - 1)

    def prepare(self, history):
        self.row(0, 0, 0, False, available=False, reset=True)
        for source in reset_prefix(history):
            self.message(1 << source, source)


def generate(output, gap):
    writer = Writer(output, gap)
    cases, certificates = [], []
    histories = tuple(itertools.product(range(3), range(5), range(2), range(4)))
    for target, history in itertools.product(range(11), histories):
        bound = service_bound(history, target)
        certificates.append(dict(target=target, history=history, **asdict(bound)))
        writer.prepare(history)
        start, count = writer.rows, writer.words
        for step in bound.steps:
            writer.message(step.pending, step.source)
        actual = writer.words - count
        if actual != bound.opportunities:
            raise ValueError('boundary witness length differs')
        cases.append(dict(mode='boundary', target=target, history=history,
                          first_row=start, end_row=writer.rows, opportunities=actual))
    for basic, control, remaining, target in itertools.product(range(5), range(2), range(1, 33), range(11)):
        history = (2, basic, control, 0)
        writer.prepare(history)
        for index in range(33 - remaining):
            writer.beat(1 << 7, 7, index, False)
        start, count = writer.rows, writer.words
        for index in range(33 - remaining, 33):
            writer.beat((1 << target) | (1 << 7), 7, index, index == 32)
        if target != 7:
            for step in service_bound(history, target).steps:
                writer.message(step.pending, step.source)
        actual = writer.words - count
        if actual != locked_service_bound(history, target, remaining):
            raise ValueError('locked witness length differs')
        cases.append(dict(mode='locked', target=target, history=history, remaining=remaining,
                          first_row=start, end_row=writer.rows, opportunities=actual))
    return dict(gap=gap, rows=writer.rows, words=writer.words, messages=writer.messages,
                stalls=writer.stalls, cases=cases, certificates=certificates)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--summary', type=Path, required=True)
    parser.add_argument('--gap', type=int, default=1)
    args = parser.parse_args()
    with args.output.open('w') as output:
        summary = generate(output, args.gap)
    args.summary.write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps({k:v for k,v in summary.items() if k not in ('cases','certificates')}))
if __name__ == '__main__':
    main()

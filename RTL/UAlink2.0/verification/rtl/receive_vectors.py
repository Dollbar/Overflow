"""Run with --depth/--width; emit stimulus, pre-edge view, post-edge view.

Output goes to stdout as hex vectors for upli_receive_storage_tb. Next run
scripts/receive.mk against the actual external KD28 SRAM model backend.
"""

import argparse
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.receive_fifo import ReceiveFifo


def vectors(depth, width):
    fifo = ReceiveFifo(depth, width)
    mask = (1 << width)-1

    def view(reset):
        v = fifo.outputs
        return (v.count << (width+2)) | (v.data << 2) | (int(v.valid) << 1) | int(v.ready and not reset)

    def edge(data=None, consume=False, reset=False):
        stimulus = (int(not reset) << (width+2)) | (int(consume) << (width+1)) | (int(data is not None) << width) | (data or 0)
        before = view(reset)
        fifo.step(data, consume, reset)
        return stimulus, before, view(reset)

    yield edge(reset=True)
    for value in range(depth):
        yield edge((value*0x1020507+0x531D) & mask)
    yield edge(mask)  # Deliberately rejected full offer, not a legal producer retry sequence.
    for _ in range(4):
        yield edge()
    # Sufficient depth must sustain simultaneous refill and drain every cycle.
    # Retain the first full-queue offer until the subsequent space is visible.
    if depth >= 4:
        word = 0
        for _ in range(128):
            accepted = fifo.outputs.ready
            yield edge((0xD705+word*0x2040B) & mask, consume=True)
            if accepted:
                word += 1
    for _ in range(depth+8):
        yield edge(consume=True)
    rng, held = random.Random(0x52584651+depth*64+width), None
    for cycle in range(4096):
        reset = cycle % 521 == 0
        if held is None and rng.randrange(5):
            held = rng.getrandbits(width)
        accepted = held is not None and fifo.outputs.ready and not reset
        yield edge(held, bool(rng.randrange(2)), reset)
        if accepted or reset:
            held = None
    if held is not None:
        while not fifo.outputs.ready:
            yield edge(held, consume=True)
        yield edge(held, consume=True)
    for _ in range(depth+8):
        yield edge(consume=True)
    assert fifo.outputs.count == 0 and not fifo.outputs.valid
    # Reset every possible SRAM request/result/cache phase and reject stale data.
    for wait in range(5):
        yield edge(0x59 & mask)
        for _ in range(wait):
            yield edge()
        yield edge(reset=True)
        for _ in range(5):
            yield edge(consume=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--depth", type=int, default=5)
    parser.add_argument("--width", type=int, default=32)
    args = parser.parse_args()
    for row in vectors(args.depth, args.width):
        print(" ".join(f"{value:x}" for value in row))


if __name__ == "__main__":
    main()

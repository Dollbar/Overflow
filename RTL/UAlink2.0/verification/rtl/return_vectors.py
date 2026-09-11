"""Normal-return queue stimulus and independent deque-model expectations.

Run: python3 verification/rtl/return_vectors.py --ports 4 --depth 5
Output: input, pre-edge ready, post-edge outputs/counts/ready as hex columns.
Next: run upli_credit_return_tb using identical port/depth parameters.
"""

import argparse
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.upli_credit import Beat
from model.ualink.upli_credit_return import CreditReturnQueue


def count_width(depth):
    if type(depth) is not int or not 1 <= depth <= 16:
        raise ValueError("depth must be an integer in 1..16")
    return depth.bit_length()


def vectors(ports, depth):
    queue = CreditReturnQueue(ports, depth)
    width = count_width(depth)

    def evaluate(stimulus):
        rstn, enable = bool(stimulus & 1024), (stimulus >> 6) & 15
        valid, port = bool(stimulus & 32), (stimulus >> 3) & 3
        old_ready = int(rstn and queue.ready(port))
        beat = Beat(port, "req", (stimulus >> 1) & 3, bool(stimulus & 1)) if valid else None
        event = queue.step(beat, enable, reset=not rstn)
        valid_mask = pool_mask = vcs = nums = 0
        for grant in event.returns:
            valid_mask |= 1 << grant.port
            pool_mask |= int(grant.pool) << grant.port
            vcs |= grant.vc << (2*grant.port)
            nums |= grant.encoded_count << (2*grant.port)
        counts = sum(count << (p*width) for p, count in enumerate(queue.pending))
        post_ready = int(rstn and queue.ready(port))
        result = (post_ready << (24+4*width)) | (counts << 24) | (valid_mask << 20) | (pool_mask << 16) | (vcs << 8) | nums
        return stimulus, old_ready, result

    for metadata in range(8):
        yield evaluate(1023)  # reset overrides every control and metadata bit
        yield evaluate(0)
        for port in range(ports):
            for _ in range(depth+2):
                yield evaluate(1024 | 32 | (port << 3) | metadata)
        for mask in (0, 5, 10, 15):
            for _ in range(depth+2):
                yield evaluate(1024 | (mask << 6))
    # Mixed head runs and simultaneous old-tail drain/new-tail append.
    yield evaluate(0)
    for port in range(ports):
        for index in range(depth):
            yield evaluate(1024 | 32 | (port << 3) | ((index//2) % 8))
    for cycle in range(4*depth+8):
        yield evaluate(1024 | (15 << 6) | 32 | ((cycle % ports) << 3) | (cycle % 8))
    # Unused address is a local rejected offer; it is cancelled by reset.
    for port in range(ports, 4):
        yield evaluate(1024 | (15 << 6) | 32 | (port << 3) | 7)
        yield evaluate(0)
    # Legal random producer retains its exact offer while backpressured.
    rng = random.Random(0x52455451+ports*256+depth)
    held = None
    for cycle in range(4096):
        if cycle % 257 == 0:
            held = None
            yield evaluate(rng.randrange(1024))
            continue
        if held is None and rng.randrange(5):
            held = 32 | (rng.randrange(ports) << 3) | rng.randrange(8)
        stimulus = 1024 | (rng.randrange(16) << 6) | (held or 0)
        row = evaluate(stimulus)
        if row[1]:
            held = None
        yield row
    # Drain any producer-held record first, then all queued and registered data.
    if held is not None:
        for _ in range(2):
            row = evaluate(1024 | (15 << 6) | held)
            yield row
            if row[1]:
                break
    for _ in range(depth+3):
        yield evaluate(1024 | (15 << 6))
    assert queue.pending == (0,)*ports and not queue.outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ports", type=int, default=1)
    parser.add_argument("--depth", type=int, default=4)
    args = parser.parse_args()
    for stimulus, ready, expected in vectors(args.ports, args.depth):
        print(f"{stimulus:03x} {ready:x} {expected:x}")


if __name__ == "__main__":
    main()

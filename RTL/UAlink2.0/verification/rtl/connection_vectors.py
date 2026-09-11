"""Emit 13-bit input/golden rows for the paired UPLI controller testbench.

Run via the project Makefile; stdout is a generated .mem artifact, not source.
4^6 readiness histories plus seeded reset traffic, for either Completer policy.
"""

import argparse
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.upli_connection import UpliConnection


def connection_vectors(wait):
    """Yield stimulus[12:10] and expected outputs[9:0] with explicit ordering."""
    model = UpliConnection(completer_waits=bool(wait))
    rng = random.Random(0x55504C49)
    for episode in range(4096):
        stimuli = [(False, False, False), (True, bool(episode & 1), bool(episode & 2))]
        stimuli += [(True, bool(episode & (1 << (2 * cycle))),
                     bool(episode & (1 << (2 * cycle + 1)))) for cycle in range(6)]
        for stimulus in stimuli:
            yield pack_row(stimulus, model.step(*stimulus))
    for _ in range(2048):
        stimulus = (rng.randrange(19) != 0, bool(rng.getrandbits(1)), bool(rng.getrandbits(1)))
        yield pack_row(stimulus, model.step(*stimulus))


def pack_row(stimulus, state):
    bits = (*stimulus, state.orig_req, state.comp_ack, state.comp_req, state.orig_ack,
            state.orig_connected, state.comp_connected, state.comp_connected,
            state.orig_connected, state.beats_enabled, state.beats_enabled)
    row = 0
    for bit in bits:
        assert type(bit) is bool
        row = (row << 1) | int(bit)
    return row


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wait", type=int, choices=(0, 1), required=True)
    args = parser.parse_args()
    for row in connection_vectors(args.wait):
        print(f"{row:04x}")

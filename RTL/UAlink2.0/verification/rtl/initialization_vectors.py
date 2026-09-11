"""Initial publisher vectors from the independent schedule model.

Run: python3 verification/rtl/initialization_vectors.py --ports 4 --width 4
Output: hex input/output columns; --capacities prints the packed capacity value.
Next: run upli_credit_initialization_tb with the same profile and vector file.
"""

import argparse
from dataclasses import dataclass
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.upli_connection import ConnectionSignals
from model.ualink.upli_credit_initialization import InitialCreditPublisher
from verification.rtl.credit_vectors import Profile


@dataclass(frozen=True)
class InitialProfile(Profile):
    """Test-only fixtures; staggered ports deliberately finish at different edges."""

    pattern: str = "standard"

    def __post_init__(self):
        super().__post_init__()
        if self.pattern not in ("standard", "staggered"):
            raise ValueError("unknown initialization capacity pattern")
        if self.pattern == "staggered" and self.uniform_capacity is not None:
            raise ValueError("staggered and uniform capacities cannot be combined")

    @property
    def capacities(self):
        if self.pattern == "standard":
            return super().capacities
        maximum = (1 << self.width)-1
        ports = ((0, 0, 0, 0, 0), (0, 0, 0, 0, maximum),
                 (0, 2, 0, 0, 0), (4, 5, 6, maximum, 0))
        return tuple(cap for port in ports[:self.ports] for cap in port)


def packed_outputs(event):
    valid = pool = vcs = nums = 0
    for grant in event.returns:
        if valid & (1 << grant.port):
            raise ValueError("duplicate per-port publication")
        valid |= 1 << grant.port
        pool |= int(grant.pool) << grant.port
        vcs |= grant.vc << (grant.port*2)
        nums |= grant.encoded_count << (grant.port*2)
    return (valid << 24) | (pool << 20) | (vcs << 12) | (nums << 4) | event.done


def stimuli(profile):
    longest = max(sum(max(1, (cap+3)//4) for cap in profile.capacities[p*5:p*5+5])
                  for p in range(profile.ports))
    # Includes completion, reset during every short phase, and a long-width midpoint.
    for cut in (longest+16, 0, 1, 2, 4, 5, 6, 10, 11, 12, 15, 31, longest//2, longest, longest+16):
        yield 1  # reset low overrides connected high
        yield 0  # repeated reset, now disconnected
        for _ in range((cut % 7)+1):
            yield 2  # released reset, wait without progressing
        for _ in range(cut):
            yield 3  # legal connection stays high until next reset


def vectors(profile):
    publisher = InitialCreditPublisher(profile.capacities, profile.ports, width=profile.width)
    for stimulus in stimuli(profile):
        connected = bool(stimulus & 1)
        event = publisher.step(ConnectionSignals(False, False, connected, connected),
                               reset=not bool(stimulus & 2))
        yield stimulus, packed_outputs(event)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ports", type=int, default=1)
    parser.add_argument("--width", type=int, default=4)
    parser.add_argument("--uniform-capacity", type=int)
    parser.add_argument("--pattern", choices=("standard", "staggered"), default="standard")
    parser.add_argument("--capacities", action="store_true")
    args = parser.parse_args()
    profile = InitialProfile(args.ports, args.width, 2, args.uniform_capacity, args.pattern)
    if args.capacities:
        print(f"{profile.packed_capacities:x}")
    else:
        for stimulus, result in vectors(profile):
            print(f"{stimulus:x} {result:07x}")


if __name__ == "__main__":
    main()

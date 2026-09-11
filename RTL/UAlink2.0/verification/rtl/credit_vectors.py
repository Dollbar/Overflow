"""Generate credit-bank vectors using the pre-existing UpliCreditLedger.

Run: python3 verification/rtl/credit_vectors.py --ports 4 --width 4 --init 2
Output: four hex columns (37-bit input, balances, confirmed, error) on stdout.
Next: feed this file to upli_credit_tb with identical profile parameters.
"""

import argparse
from dataclasses import dataclass
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.upli_connection import ConnectionSignals
from model.ualink.upli_credit import Account, Beat, CreditReturn, UpliCreditLedger


@dataclass(frozen=True)
class Profile:
    ports: int
    width: int
    init: int
    uniform_capacity: int | None = None

    def __post_init__(self):
        if self.ports not in (1, 2, 4) or not 3 <= self.width <= 16 or not 2 <= self.init <= 15:
            raise ValueError("profile requires ports 1/2/4, width 3..16, init 2..15")
        if self.uniform_capacity is not None and (type(self.uniform_capacity) is not int or not 0 <= self.uniform_capacity < (1 << self.width)):
            raise ValueError("uniform capacity must fit the credit width")

    @property
    def capacities(self):
        if self.uniform_capacity is not None:
            return (self.uniform_capacity,) * (self.ports * 5)
        base = (0, 1, 3, 4, (1 << self.width) - 1)
        return tuple(c for p in range(self.ports) for c in (base if p % 2 == 0 else base[::-1]))

    @property
    def packed_capacities(self):
        return sum(c << (i * self.width) for i, c in enumerate(self.capacities))


@dataclass(frozen=True)
class Stimulus:
    rstn: int = 1
    credit_connected: int = 1
    beats_connected: int = 1
    valid: int = 0
    pool: int = 0
    vc: int = 0
    num: int = 0
    init_done: int = 0
    send_valid: int = 0
    send_port: int = 0
    send_vc: int = 0
    send_pool: int = 0

    def packed(self):
        result = 0
        for field, width in zip(self.__dataclass_fields__, (1, 1, 1, 4, 4, 8, 8, 4, 1, 2, 2, 1)):
            value = getattr(self, field)
            if type(value) is not int or not 0 <= value < (1 << width):
                raise ValueError(f"invalid {field} field")
            result = (result << width) | value
        return result


class Oracle:
    def __init__(self, profile):
        self.profile = profile
        self.accounts = tuple(Account(p, "req", None if a == 4 else a)
                              for p in range(profile.ports) for a in range(5))
        self.ledger = UpliCreditLedger(dict(zip(self.accounts, profile.capacities)), profile.ports, profile.init)

    def step(self, s):
        s.packed()  # Reject truncating the physical vector before model evaluation.
        if s.rstn and s.beats_connected and not s.credit_connected:
            raise ValueError("inconsistent integration connection flags")
        conn = ConnectionSignals(bool(s.beats_connected), bool(s.beats_connected),
                                 bool(s.credit_connected), bool(s.credit_connected))
        returns = [CreditReturn(p, "req", (s.vc >> (2*p)) & 3, bool((s.pool >> p) & 1),
                                (s.num >> (2*p)) & 3) for p in range(4) if (s.valid >> p) & 1]
        beats = [Beat(s.send_port, "req", s.send_vc, bool(s.send_pool))] if s.send_valid else []
        done = [(p, "req") for p in range(4) if (s.init_done >> p) & 1]
        error = 0
        try:
            self.ledger.step(conn, returns=returns, beats=beats, init_done=done, reset=not bool(s.rstn))
        except ValueError:
            error = 1
        balances = sum(self.ledger.balance(a) << (i*self.profile.width) for i, a in enumerate(self.accounts))
        confirmed = sum(int(self.ledger.initialized(p, "req")) << p for p in range(self.profile.ports))
        return balances, confirmed, error


def stimuli(profile):
    """Directed independent accounts, then seeded valid and deliberately bad edges."""
    mask = (1 << profile.ports) - 1
    yield Stimulus(rstn=0, valid=15, init_done=15, send_valid=1)
    yield Stimulus(credit_connected=0, beats_connected=0, valid=mask)
    yield Stimulus(credit_connected=0, beats_connected=0, init_done=mask)
    yield Stimulus(pool=15, vc=255, num=255, send_port=3)
    for p in range(profile.ports, 4):
        yield Stimulus(valid=1 << p)
        yield Stimulus(init_done=1 << p)
        yield Stimulus(send_valid=1, send_port=p)
    for p in range(profile.ports):
        for a in range(5):
            cap = profile.capacities[p*5+a]
            ret = dict(valid=1 << p, pool=(1 << p) if a == 4 else 0, vc=(a % 4) << (2*p))
            send = dict(send_valid=1, send_port=p, send_vc=a % 4, send_pool=int(a == 4))
            yield Stimulus(rstn=0)
            # Encoding 0,1,2,3 represents 1,2,3,4 even at a too-small capacity.
            for enc in range(4):
                yield Stimulus(**ret, num=enc << (2*p))
                yield Stimulus(rstn=0)
            yield Stimulus(**ret, **send, init_done=1 << p)  # No new credit/init bypass.
            yield Stimulus(rstn=0)
            for _ in range(profile.init-1):
                yield Stimulus(init_done=1 << p)
            yield Stimulus()  # A short init pulse must not confirm.
            for _ in range(profile.init):
                yield Stimulus(init_done=1 << p)
            yield Stimulus(**ret, **send)  # Initialized but empty: return cannot bypass.
            yield Stimulus(**send)  # Still empty after failed atomic edge.
            for amount in range(0, cap, 4):
                yield Stimulus(**ret, num=(min(4, cap-amount)-1) << (2*p))
            yield Stimulus(**ret, **send)  # Net zero at full: legal only if cap > 0.
            yield Stimulus(**ret)  # Overflow, including zero-capacity accounts.
            yield Stimulus(beats_connected=0, **send)
            yield Stimulus(credit_connected=0, beats_connected=0, init_done=1 << p)
            for n in range(cap):
                pool_send = dict(send, send_vc=n % 4) if a == 4 else send
                yield Stimulus(**pool_send)
            yield Stimulus(**send)
    # All ports can return independently of any data TDM slot.
    yield Stimulus(rstn=0)
    for a in (1, 2, 3):
        yield Stimulus(valid=mask, vc=sum(a << (2*p) for p in range(profile.ports)))
    for _ in range(profile.init-1):
        yield Stimulus(init_done=mask)
    yield Stimulus(init_done=mask, send_valid=1, send_vc=1)  # Confirmation edge is too early.
    yield Stimulus(init_done=mask)
    yield Stimulus(send_valid=1, send_vc=1)
    rng = random.Random(0x43524454 + profile.ports*256 + profile.width*16 + profile.init)
    for cycle in range(2048):
        if cycle % 128 == 0:
            yield Stimulus(rstn=0)
        elif cycle % 128 < profile.init+1:
            yield Stimulus(init_done=mask)
        else:
            cc = int(rng.randrange(20) != 0)
            yield Stimulus(credit_connected=cc, beats_connected=cc & int(rng.randrange(10) != 0),
                           valid=rng.randrange(16), pool=rng.randrange(16), vc=rng.randrange(256),
                           num=rng.randrange(256), init_done=rng.randrange(mask+1),
                           send_valid=rng.randrange(2), send_port=rng.randrange(4),
                           send_vc=rng.randrange(4), send_pool=rng.randrange(2))


def vectors(profile):
    oracle = Oracle(profile)
    for stimulus in stimuli(profile):
        yield (stimulus.packed(), *oracle.step(stimulus))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ports", type=int, default=1)
    parser.add_argument("--width", type=int, default=4)
    parser.add_argument("--init", type=int, default=2)
    parser.add_argument("--uniform-capacity", type=int, help="override all account capacities for synthesis-profile comparison")
    parser.add_argument("--capacities", action="store_true", help="print packed parameter hex instead")
    args = parser.parse_args()
    profile = Profile(args.ports, args.width, args.init, args.uniform_capacity)
    if args.capacities:
        print(f"{profile.packed_capacities:x}")
    else:
        for row in vectors(profile):
            print(" ".join(f"{field:x}" for field in row))


if __name__ == "__main__":
    main()

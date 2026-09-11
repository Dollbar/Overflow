"""Run: python3 verification/rtl/burst_control_vectors.py --ports 4.

Output: hexadecimal inputs, pre-edge events/state, post-edge state for the
actual control TB. Next: compare RTL, then integrate real banks and payload.
Oracle is the pre-existing burst model plus an independent passive monitor;
these vectors do not pretend to simulate receiver SRAM or connection FSM RTL.
"""

import argparse
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.upli_burst import BurstRequest, UpliBurstSender
from model.ualink.upli_burst_monitor import UpliBurstMonitor
from model.ualink.upli_connection import ConnectionSignals
from model.ualink.upli_credit import Account, CreditReturn


def packed(fields):
    result = 0
    for value, width in fields:
        if not 0 <= value < (1 << width):
            raise ValueError("vector field cannot fit its declared width")
        result = (result << width) | value
    return result


class Oracle:
    def __init__(self, ports, width):
        self.ports, self.width = ports, width
        self.capacities = {Account(p, ch, vc): 4 for p in range(ports)
                           for ch in ("req", "orig_data") for vc in (0, 1, 2, 3, None)}
        self.sender = UpliBurstSender(self.capacities, ports)
        self.monitor = UpliBurstMonitor(ports)
        self.rows = self.requests = self.data = self.overlays = 0

    def state(self):
        busy = sum((any(self.sender.reserved(Account(p, "orig_data", vc))
                        for vc in (0, 1, 2, 3, None))) << p for p in range(self.ports))
        phase = self.sender.next_port
        return packed(((busy, 4), (int(phase is not None), 1), (phase or 0, 2)))

    def emit(self, request=None, *, returns=(), init=(), connected=True, reset=False,
             invalid_port=None, unused_pools=0):
        before = self.state()
        banks = []
        confirmed = []
        for ch in ("req", "orig_data"):
            banks.append(sum(self.sender.balance(Account(p, ch, vc)) <<
                             ((p*5+a)*self.width) for p in range(self.ports)
                             for a, vc in enumerate((0, 1, 2, 3, None))))
            confirmed.append(sum(self.sender.initialized(p, ch) << p for p in range(self.ports)))
        req = request
        pool_bits = sum(int(pool) << i for i, pool in enumerate(req.data_pools)) if req else 0
        if req and req.num_beats is not None:
            pool_bits |= unused_pools & (15 ^ ((1 << (req.num_beats+1))-1))
        inp = packed(((int(not reset), 1), (int(connected), 1),
                      (int(req is not None or invalid_port is not None), 1),
                      (invalid_port if invalid_port is not None else req.port if req else 0, 2),
                      (req.vc if req else 0, 2), (int(req.pool) if req else 0, 1),
                      (int(req.num_beats is not None) if req else 0, 1),
                      ((req.num_beats or 0) if req else 0, 2), (pool_bits, 4),
                      (confirmed[0], 4), (confirmed[1], 4),
                      (banks[0], self.ports*5*self.width), (banks[1], self.ports*5*self.width)))
        connection = ConnectionSignals(*([connected]*4))
        events = self.sender.step(connection, request=req, returns=returns, init_done=init, reset=reset)
        self.monitor.step(events.request, events.data, reset=reset)
        out_req, out_data = events.request, events.data
        result = packed(((int(out_req is not None), 1),
                         (out_req.port if out_req else 0, 2), (out_req.vc if out_req else 0, 2),
                         (int(out_req.pool) if out_req else 0, 1),
                         (int(out_data is not None), 1), (out_data.port if out_data else 0, 2),
                         (out_data.vc if out_data else 0, 2), (int(out_data.pool) if out_data else 0, 1),
                         (out_data.offset if out_data else 0, 2), (int(out_data.last) if out_data else 0, 1),
                         (before, 7)))
        print(f"{inp:x} {result:x} {self.state():x}")
        self.rows += 1
        self.requests += out_req is not None
        self.data += out_data is not None
        self.overlays += out_req is not None and out_req.num_beats is None and out_data is not None
        return events

    def bootstrap(self, blocked=None, amounts=None):
        self.emit(reset=True)
        self.emit(blocked, connected=False)
        amounts = amounts or {}
        for vc in (0, 1, 2, 3, None):
            credits = []
            for port in range(self.ports):
                for channel in ("req", "orig_data"):
                    count = amounts.get(Account(port, channel, vc), 4)
                    if count:
                        credits.append(CreditReturn(port, channel, vc or 0, vc is None, count-1))
            assert not self.emit(blocked, returns=credits).accepted
        init = [(p, ch) for p in range(self.ports) for ch in ("req", "orig_data")]
        assert not self.emit(blocked, init=init).accepted
        assert not self.emit(blocked, init=init).accepted


def generate(ports, width):
    oracle = Oracle(ports, width)
    cases = 0
    for start in range(ports):
        for vc in range(4):
            for num in range(4):
                for pools in range(1 << (num+1)):
                    pattern = tuple(bool(pools & (1 << i)) for i in range(num+1))
                    for req_pool in (False, True):
                        request = BurstRequest(start, vc, req_pool, num, pattern)
                        oracle.bootstrap(request)
                        first = oracle.emit(request, unused_pools=15)
                        assert first.accepted and first.data.offset == 0
                        assert first.data.last == (num == 0)
                        # Keep a new write pending in every old data slot, including
                        # the last; alternate read-class to expose old/new VC mixing.
                        for cycle in range(num*ports):
                            candidate = (BurstRequest(start, (vc+1) % 4, not req_pool)
                                         if cycle % 2 else request)
                            event = oracle.emit(candidate, unused_pools=15)
                            if candidate.num_beats is not None:
                                assert not event.accepted
                        for _ in range(3):
                            oracle.emit()
                        cases += 1
    # Hand-derived demand: two pool plus two VC credits for pools 0101.
    mix = BurstRequest(ports-1, 3, True, 3, (True, False, True, False))
    for vc_account in (None, 3):
        account = Account(ports-1, "orig_data", vc_account)
        oracle.bootstrap(mix, {account: 1})
        assert not oracle.emit(mix).accepted
        added = CreditReturn(ports-1, "orig_data", vc_account or 0, vc_account is None, 0)
        assert not oracle.emit(mix, returns=[added]).accepted
        assert oracle.emit(mix).accepted
        for _ in range(3*ports):
            oracle.emit()
    # All independent ports can own a burst concurrently; read overlays remain legal.
    oracle.bootstrap()
    for p in range(ports):
        assert oracle.emit(BurstRequest(p, p, False, 3, (False, True, False, True))).accepted
    assert oracle.state() >> 3 == (1 << ports)-1
    for _ in range(3*ports):
        oracle.emit(BurstRequest(oracle.sender.next_port, 3, True))
    # Reset cancels old reservations and forgets first-request phase.
    oracle.bootstrap()
    oracle.emit(BurstRequest(ports-1, 2, True, 3, (True,)*4))
    oracle.emit(reset=True, request=mix)
    for _ in range(5):
        oracle.emit(mix)
    oracle.bootstrap()
    if ports < 4:
        for _ in range(7):
            oracle.emit(invalid_port=ports)
        assert oracle.sender.next_port is None
    # Deterministic varying candidates/idle cycles with valid returned credit deficits.
    rng = random.Random(0x42555253+ports)
    for cycle in range(500):
        ret = []
        account_vc = (0, 1, 2, 3, None)[cycle % 5]
        for p in range(ports):
            for ch in ("req", "orig_data"):
                missing = 4-oracle.sender.balance(Account(p, ch, account_vc))
                if missing:
                    ret.append(CreditReturn(p, ch, account_vc or 0, account_vc is None, missing-1))
        num = rng.randrange(4)
        candidate = BurstRequest(rng.randrange(ports), rng.randrange(4), bool(rng.randrange(2)),
                                 num, tuple(bool(rng.randrange(2)) for _ in range(num+1)))
        oracle.emit(candidate if cycle % 5 else None, returns=ret, unused_pools=15)
    for _ in range(4*ports):
        oracle.emit()
    assert oracle.state() >> 3 == 0
    print(f"ORACLE rows={oracle.rows} allocation_cases={cases} requests={oracle.requests} "
          f"data={oracle.data} read_overlays={oracle.overlays} ports={ports}", file=sys.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ports", type=int, choices=(1, 2, 4), default=1)
    parser.add_argument("--credit-width", type=int, choices=range(3, 17), default=4)
    args = parser.parse_args()
    generate(args.ports, args.credit_width)

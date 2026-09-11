"""Run: python3 verification/rtl/burst_payload_vectors.py --ports 4.

Output: input/event/pre-state/post-state hex rows on stdout, counts on stderr.
Next: run the actual sender, including its two credit banks, with payload.mk.
The independent immutable-tuple payload model owns expected data. A passive
monitor checks the model's protocol events. Invalid credit edges are excluded:
model exception rollback is not the hardware's per-channel diagnostic policy.
The final, separately hand-derived idle diagnostic rows do exercise that policy.
"""

import argparse
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.upli_burst import BurstRequest
from model.ualink.upli_burst_payload import OrigDataPayload, StagedBurst, UpliBurstPayload
from model.ualink.upli_burst_monitor import UpliBurstMonitor
from model.ualink.upli_connection import ConnectionSignals
from model.ualink.upli_credit import Account, CreditReturn


def packed(fields):
    result = 0
    for value, width in fields:
        if not 0 <= value < (1 << width):
            raise ValueError("vector field exceeds its declared width")
        result = (result << width) | value
    return result


class Oracle:
    def __init__(self, ports, width, request_width, init_cycles):
        self.ports, self.width = ports, width
        self.request_width, self.init_cycles = request_width, init_cycles
        capacities = {Account(p, ch, vc): 4 for p in range(ports)
                      for ch in ("req", "orig_data") for vc in (0, 1, 2, 3, None)}
        self.sender = UpliBurstPayload(capacities, ports, request_width=request_width,
                                       init_stable_cycles=init_cycles)
        self.monitor = UpliBurstMonitor(ports)
        self.rng = random.Random(0x5041594C + ports)
        self.rows = self.requests = self.data = self.overlays = self.serial = 0
        self.init_high = set()

    def candidate(self, port, vc, pool=False, num=None, pools=0):
        self.serial += 1
        req = BurstRequest(port, vc, pool, num,
                           tuple(bool(pools & (1 << n)) for n in range(num+1))
                           if num is not None else ())
        data = tuple(OrigDataPayload(self.rng.getrandbits(512), self.rng.getrandbits(64),
                                    bool((self.serial+n) % 2))
                     for n in range(num+1)) if num is not None else ()
        return StagedBurst(req, self.rng.getrandbits(self.request_width), data)

    def state(self):
        busy = sum(int(any(self.sender.reserved(Account(p, "orig_data", vc))
                           for vc in (0, 1, 2, 3, None))) << p for p in range(self.ports))
        banks, init = [], []
        for ch in ("req", "orig_data"):
            banks.append(sum(self.sender.balance(Account(p, ch, vc)) << ((p*5+a)*self.width)
                             for p in range(self.ports) for a, vc in enumerate((0, 1, 2, 3, None))))
            init.append(sum(self.sender.initialized(p, ch) << p for p in range(self.ports)))
        return packed(((busy, 4), (int(self.sender.next_port is not None), 1),
                       (self.sender.next_port or 0, 2), (banks[0], self.ports*5*self.width),
                       (banks[1], self.ports*5*self.width), (init[0], 4), (init[1], 4), (0, 3)))

    def return_fields(self, channel, returns):
        valid = pool = vc = num = init = 0
        for grant in returns:
            if grant.channel != channel:
                continue
            if valid & (1 << grant.port):
                raise ValueError("duplicate channel/port grant")
            valid |= 1 << grant.port
            pool |= int(grant.pool) << grant.port
            vc |= grant.vc << (2*grant.port)
            num |= grant.encoded_count << (2*grant.port)
        for p, ch in self.init_high:
            if ch == channel:
                init |= 1 << p
        return packed(((valid, 4), (pool, 4), (vc, 8), (num, 8), (init, 4)))

    def emit(self, candidate=None, *, returns=(), credit_connected=True,
             beats_connected=True, reset=False, init=None, invalid_port=None):
        if reset:
            self.init_high.clear()
        elif init is not None:
            self.init_high = set(init)
        before = self.state()
        # Invalid/unused candidate fields deliberately toggle even without valid.
        raw = candidate or self.candidate(0, 3, True, 3, 15)
        req = raw.request
        words = list(raw.data)
        while len(words) < 4:
            words.append(OrigDataPayload(self.rng.getrandbits(512), self.rng.getrandbits(64), True))
        pools = sum(int(pool) << n for n, pool in enumerate(req.data_pools))
        used = (1 << len(req.data_pools))-1
        pools |= 15 ^ used  # Unused high pool bits must not add to the credit demand.
        inp = packed(((int(not reset), 1), (int(credit_connected), 1), (int(beats_connected), 1),
                      (int(candidate is not None or invalid_port is not None), 1),
                      (invalid_port if invalid_port is not None else req.port, 2), (req.vc, 2),
                      (int(req.pool), 1), (int(req.num_beats is not None), 1), (req.num_beats or 0, 2),
                      (pools, 4), (raw.request_payload, self.request_width),
                      (sum(w.data << (512*n) for n, w in enumerate(words)), 2048),
                      (sum(w.byte_enable << (64*n) for n, w in enumerate(words)), 256),
                      (sum(int(w.error) << n for n, w in enumerate(words)), 4),
                      (self.return_fields("req", returns), 28),
                      (self.return_fields("orig_data", returns), 28)))
        connection = ConnectionSignals(beats_connected, beats_connected,
                                       credit_connected, credit_connected)
        events = self.sender.step(connection, candidate=candidate, returns=returns,
                                  init_done=self.init_high, reset=reset)
        req_out, data_out = events.control.request, events.control.data
        word = events.data_payload
        self.monitor.step(req_out, data_out, reset=reset)
        out = packed(((int(req_out is not None), 1), (req_out.port if req_out else 0, 2),
                      (req_out.vc if req_out else 0, 2), (int(req_out.pool) if req_out else 0, 1),
                      (int(data_out is not None), 1), (data_out.port if data_out else 0, 2),
                      (data_out.vc if data_out else 0, 2), (int(data_out.pool) if data_out else 0, 1),
                      (data_out.offset if data_out else 0, 2), (int(data_out.last) if data_out else 0, 1),
                      (events.request_payload or 0, self.request_width),
                      (word.data if word else 0, 512), (word.byte_enable if word else 0, 64),
                      (int(word.error) if word else 0, 1)))
        print(f"{inp:x} {out:x} {before:x} {self.state():x}")
        self.rows += 1
        self.requests += req_out is not None
        self.data += data_out is not None
        self.overlays += req_out is not None and req_out.num_beats is None and data_out is not None
        return events

    def bootstrap(self, blocked=None, amounts=None):
        self.emit(reset=True)
        self.emit(blocked, credit_connected=False, beats_connected=False)
        amounts = amounts or {}
        for vc in (0, 1, 2, 3, None):
            returns = []
            for p in range(self.ports):
                for ch in ("req", "orig_data"):
                    count = amounts.get(Account(p, ch, vc), 4)
                    if count:
                        returns.append(CreditReturn(p, ch, vc or 0, vc is None, count-1))
            assert not self.emit(blocked, returns=returns, beats_connected=False).control.accepted
        init = [(p, ch) for p in range(self.ports) for ch in ("req", "orig_data")]
        # Short high then low exercises the actual banks' pre-confirmation filter.
        assert not self.emit(blocked, init=init).control.accepted
        assert not self.emit(blocked, init=()).control.accepted
        for _ in range(self.init_cycles):
            assert not self.emit(blocked, init=init).control.accepted


def diagnostics(ports, width, request_width, initial_state):
    """Hand-derived idle credit faults, not the exception-rollback model.

    No traffic is sent here. Tests check independent banks, registered one-edge
    errors, persistent diagnostics, unused-port controls and reset. This does
    not assert that damaged credit during an active burst has been recovered.
    """
    state = initial_state
    rows = 0

    def expected(req=0, data=0, errors=0, req_init=0, data_init=0):
        return packed(((0, 7), (req, ports*5*width), (data, ports*5*width),
                       (req_init, 4), (data_init, 4), (errors, 3)))

    def grant(port=0, vc=0, count=1, *, init=0):
        return packed(((1 << port, 4), (0, 4), (vc << (2*port), 8),
                       ((count-1) << (2*port), 8), (init, 4)))

    def emit(after, *, reset=False, connected=True, req=0, data=0):
        nonlocal state, rows
        # All candidate fields zero and invalid: only bank diagnostic behavior.
        inp = packed(((int(not reset), 1), (int(connected), 1), (int(connected), 1),
                      (0, 13+request_width+2308), (req, 28), (data, 28)))
        print(f"{inp:x} 0 {state:x} {after:x}")
        state, rows = after, rows+1

    emit(0, reset=True)
    emit(expected(errors=5), connected=False, req=grant())  # Req error + sticky, no credit.
    for _ in range(3):
        emit(expected(errors=1))  # Pulsed bank error clears; saved diagnostic must not.
    emit(0, reset=True)
    emit(expected(req=4, data=2), req=grant(count=4), data=grant(count=2))
    data_balance = 2+(3 << width)  # VC0=2, VC1=3, all other accounts zero.
    emit(expected(req=4, data=data_balance, errors=5), req=grant(), data=grant(vc=1, count=3))
    req_balance = 4+(2 << width)  # Req overflow held channel; next legal VC1 grant commits.
    emit(expected(req=req_balance, data=data_balance, errors=3),
         req=grant(vc=1, count=2), data=grant(count=4))  # Data VC0 would become6>4.
    for _ in range(3):
        emit(expected(req=req_balance, data=data_balance, errors=1))
    emit(0, reset=True)
    emit(expected(errors=5), connected=False, req=1)  # Raw init_done before credit connection.
    emit(expected(errors=1))
    emit(0, reset=True)
    if ports < 4:
        emit(expected(data=1 << (2*width), errors=5), req=grant(port=ports), data=grant(vc=2))
        emit(expected(data=1 << (2*width), errors=1))
        emit(0, reset=True)
        emit(expected(req=1, errors=3), req=grant(), data=1 << ports)  # Unused data init port.
        emit(expected(req=1, errors=1))
        emit(0, reset=True)
    # Reset suppresses malformed credit controls and wins over both errors.
    emit(0, reset=True, connected=False, req=(1 << 28)-1, data=(1 << 28)-1)
    emit(0)
    print(f"DIAGNOSTIC idle_rows={rows} per_channel_hold=true sticky=true reset=true "
          f"unused_ports={ports < 4} active_fault_recovery=false", file=sys.stderr)
    return rows


def generate(ports, width, request_width, init_cycles):
    oracle = Oracle(ports, width, request_width, init_cycles)
    cases = 0
    # Literal ownership trace: high/low data and BE bits, alternating Error,
    # full-width opaque field. Expected output is not reconstructed from RTL.
    oracle.bootstrap()
    literal = StagedBurst(BurstRequest(ports-1, 2, True, 3, (True, False, True, False)),
                         (1 << request_width)-1,
                         tuple(OrigDataPayload((1 << 511) | (n+1), (1 << 63) | (1 << n), bool(n % 2))
                               for n in range(4)))
    event = oracle.emit(literal)
    assert event.data_payload == OrigDataPayload((1 << 511) | 1, (1 << 63) | 1, False)
    assert oracle.sender.balance(Account(ports-1, "orig_data", None)) == 3
    assert oracle.sender.reserved(Account(ports-1, "orig_data", None)) == 1
    for _ in range(3*ports):
        oracle.emit(oracle.candidate(ports-1, 1, False))
    for start in range(ports):
        for vc in range(4):
            for num in range(4):
                for pools in range(1 << (num+1)):
                    for req_pool in (False, True):
                        candidate = oracle.candidate(start, vc, req_pool, num, pools)
                        oracle.bootstrap(candidate)
                        assert oracle.emit(candidate).control.accepted
                        for cycle in range(num*ports):
                            raw = oracle.candidate(start, (vc+1) % 4, not req_pool,
                                                   None if cycle % 2 else 3, 10)
                            result = oracle.emit(raw)
                            if raw.request.num_beats is not None:
                                assert not result.control.accepted
                        oracle.emit()
                        cases += 1
    # Whole-transaction shortage, new-return non-bypass, rejected payload not captured.
    for channel, account_vc, count in (("req", None, 0), ("orig_data", None, 1), ("orig_data", 3, 1)):
        blocked = oracle.candidate(ports-1, 3, True, 3, 5)
        oracle.bootstrap(blocked, {Account(ports-1, channel, account_vc): count})
        assert not oracle.emit(blocked).control.accepted
        grant = CreditReturn(ports-1, channel, account_vc or 0, account_vc is None, 0)
        assert not oracle.emit(blocked, returns=[grant]).control.accepted
        replacement = oracle.candidate(ports-1, 3, True, 3, 5)
        assert oracle.emit(replacement).control.accepted
        for _ in range(3*ports):
            oracle.emit()
    oracle.bootstrap()
    for p in range(ports):
        assert oracle.emit(oracle.candidate(p, p, False, 3, 10)).control.accepted
    for _ in range(3*ports):
        oracle.emit(oracle.candidate(oracle.sender.next_port, 3, True))
    # Reset an unfinished burst, then all-old-state must remain inaccessible.
    oracle.bootstrap()
    oracle.emit(literal)
    oracle.emit(literal, reset=True)
    for _ in range(5):
        assert not oracle.emit(literal).control.accepted
    oracle.bootstrap()
    if ports < 4:
        for _ in range(5):
            oracle.emit(invalid_port=ports)
        assert oracle.sender.next_port is None
    for cycle in range(700):
        returns = []
        vc = (0, 1, 2, 3, None)[cycle % 5]
        for p in range(ports):
            for ch in ("req", "orig_data"):
                missing = 4-oracle.sender.balance(Account(p, ch, vc))
                if missing:
                    returns.append(CreditReturn(p, ch, vc or 0, vc is None, missing-1))
        candidate = oracle.candidate(oracle.rng.randrange(ports), oracle.rng.randrange(4),
                                     bool(oracle.rng.randrange(2)), oracle.rng.randrange(4),
                                     oracle.rng.randrange(16))
        oracle.emit(candidate if cycle % 5 else None, returns=returns)
    for _ in range(4*ports):
        oracle.emit()
    assert all(oracle.sender.reserved(Account(p, "orig_data", vc)) == 0
               for p in range(ports) for vc in (0, 1, 2, 3, None))
    print(f"ORACLE rows={oracle.rows} allocation_cases={cases} requests={oracle.requests} "
          f"data={oracle.data} read_overlays={oracle.overlays} ports={ports} "
          f"request_width={request_width} init_cycles={init_cycles}", file=sys.stderr)
    diagnostics(ports, width, request_width, oracle.state())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ports", type=int, choices=(1, 2, 4), default=1)
    parser.add_argument("--credit-width", type=int, choices=range(3, 17), default=4)
    parser.add_argument("--request-width", type=int, choices=range(1, 1025), default=96)
    parser.add_argument("--init-cycles", type=int, choices=range(2, 16), default=2)
    args = parser.parse_args()
    generate(args.ports, args.credit_width, args.request_width, args.init_cycles)

"""Emit pre/post-edge channel plus sender-ledger vectors on stdout.

Run: python3 verification/rtl/receive_channel_vectors.py --ports 1 --capacity-hex 50132
Next: make -f scripts/receive.mk sim-receive-channel with matching parameters.
Payload and original metadata also have an independent RTL testbench scoreboard.
"""

import argparse
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from model.ualink.upli_connection import ConnectionSignals
from model.ualink.upli_credit import Account, Beat, CHANNELS, UpliCreditLedger
from model.ualink.upli_receive import ReceivedBeat, ReceiveStep, UpliReceiveChannel


def pack(fields):
    result = 0
    for value, width in fields:
        if not 0 <= value < (1 << width):
            raise ValueError("vector field overflow")
        result = (result << width) | value
    return result


def packed_low(values, width):
    return sum(value << (index*width) for index, value in enumerate(values))


def vectors(ports, payload_width, credit_width, capacities, return_depth, channel):
    receiver = UpliReceiveChannel(capacities, ports, payload_width, credit_width, return_depth, channel)
    accounts = [Account(port, channel, None if account == 4 else account)
                for port in range(ports) for account in range(5)]
    sender = UpliCreditLedger(dict(zip(accounts, capacities)), ports)
    connected = ConnectionSignals(True, True, True, True)
    only_return = (ConnectionSignals(False, False, True, True) if channel in ("req", "orig_data")
                   else ConnectionSignals(True, True, False, False))
    rng = random.Random(0x55414C+ports*1024+payload_width+CHANNELS.index(channel))
    last = ReceiveStep()
    count_width, pending_width = ports*5*credit_width, return_depth.bit_length()

    def view(consumer, reset):
        signals = receiver.outputs
        head = receiver.peek(*consumer)
        item = head.received
        return pack([
            (packed_low([sender.balance(account) for account in accounts], credit_width), count_width),
            (sum(int(sender.initialized(port, channel)) << port for port in range(ports)), 4), (0, 1),
            (packed_low(signals.counts, credit_width), count_width),
            (packed_low(signals.pending, pending_width), 4*pending_width),
            (sum(1 << grant.port for grant in signals.returns), 4),
            (sum(int(grant.pool) << grant.port for grant in signals.returns), 4),
            (sum(grant.vc << (2*grant.port) for grant in signals.returns), 8),
            (sum(grant.encoded_count << (2*grant.port) for grant in signals.returns), 8), (signals.done, 4),
            (0 if item is None else item.payload, payload_width),
            (0 if item is None else item.beat.vc, 2), (int(item is not None and item.beat.pool), 1),
            (int(item is not None), 1), (int(head.ready and not reset), 1),
            (int(last.accepted), 1), (last.diagnostic, 3),
        ])

    def edge(connection=connected, incoming=None, consumer=(0, 0), consume=False, reset=False, legal=True):
        nonlocal last
        beat = incoming.beat if incoming is not None else Beat(0, channel, 0)
        send = incoming is not None and legal
        stimulus = pack([(int(not reset), 1), (int(connection.orig_req), 1), (int(connection.comp_ack), 1),
                         (int(connection.comp_req), 1), (int(connection.orig_ack), 1), (int(send), 1),
                         (int(incoming is not None), 1), (beat.port, 2), (beat.vc, 2), (int(beat.pool), 1),
                         (0 if incoming is None else incoming.payload, payload_width),
                         (consumer[0], 2), (consumer[1], 3), (int(consume), 1)])
        before = view(consumer, reset)
        signals = receiver.outputs
        sender.step(connection, returns=signals.returns, beats=(beat,) if send else (),
                    init_done=[(port, channel) for port in range(ports) if signals.done & (1 << port)], reset=reset)
        last = receiver.step(connection, incoming, consumer, consume, reset)
        return stimulus, before, view(consumer, reset)

    yield edge(ConnectionSignals(), reset=True)
    # Inactive-port, disconnected and before-init injection never reaches sender bank.
    if ports < 4:
        yield edge(ConnectionSignals(), ReceivedBeat(Beat(3, channel, 0), 1), legal=False)
    yield edge(ConnectionSignals(), ReceivedBeat(Beat(0, channel, 0), 2 & ((1 << payload_width)-1)), legal=False)
    yield edge(connected, ReceivedBeat(Beat(0, channel, 0), 3 & ((1 << payload_width)-1)), legal=False)
    # Restart legally, then exercise credit-return direction before bidirectional data.
    yield edge(ConnectionSignals(), reset=True)
    for cycle in range(4):
        yield edge(only_return, ReceivedBeat(Beat(0, channel, 0), cycle & ((1 << payload_width)-1)), legal=False)
    early_slot = None
    for _ in range(max(sum(capacities[port*5:port*5+5]) for port in range(ports))+24):
        item = None
        if early_slot is None:
            for slot, account in enumerate(accounts):
                if sender.initialized(account.port, channel) and sender.balance(account):
                    early_slot = slot
                    item = ReceivedBeat(Beat(account.port, channel, 3 if account.vc is None else account.vc,
                                             account.vc is None), 1)
                    break
        yield edge(incoming=item, consumer=divmod(early_slot or 0, 5), consume=True)
    # Fill all exact capacities without consumption; then inject one rejected full beat.
    for slot, capacity in enumerate(capacities):
        for index in range(capacity):
            port, account = divmod(slot, 5)
            yield edge(incoming=ReceivedBeat(Beat(port, channel, index % 4 if account == 4 else account, account == 4),
                                             (1+slot*257+index) & ((1 << payload_width)-1)))
        port, account = divmod(slot, 5)
        yield edge(incoming=ReceivedBeat(Beat(port, channel, 3 if account == 4 else account, account == 4), 0), legal=False)
    for cycle in range(sum(capacities)*3+20):
        yield edge(consumer=divmod(cycle % len(accounts), 5), consume=True)
    # A depth >=4 account with return depth >=2 can maintain one word per edge.
    streaming = max(range(len(capacities)), key=lambda slot: capacities[slot]) if max(capacities) >= 4 else None
    if streaming is not None:
        account = accounts[streaming]
        for cycle in range(256):
            item = (ReceivedBeat(Beat(account.port, channel, cycle % 4 if account.vc is None else account.vc,
                                      account.vc is None), cycle & ((1 << payload_width)-1))
                    if sender.balance(account) else None)
            yield edge(incoming=item, consumer=divmod(streaming, 5), consume=True)
    # Random legal traffic, arbitrary account selection, backpressure, then full drain.
    for cycle in range(3072):
        slot = rng.randrange(len(accounts))
        account = accounts[slot]
        item = None
        if sender.balance(account) and rng.randrange(4):
            item = ReceivedBeat(Beat(account.port, channel, rng.randrange(4) if account.vc is None else account.vc,
                                     account.vc is None), rng.getrandbits(payload_width))
        yield edge(incoming=item, consumer=(rng.randrange(4), rng.randrange(8)), consume=bool(rng.randrange(3)))
    for cycle in range((max(capacities)+8)*len(accounts)*3):
        yield edge(consumer=divmod(cycle % len(accounts), 5), consume=True)
    assert receiver.outputs.counts == (0,)*len(accounts)
    assert receiver.outputs.pending == (0,)*ports
    assert [sender.balance(account) for account in accounts] == list(capacities)
    # Abort real unread/read-pending/cache/return states and check no stale ownership.
    active = next((slot for slot, capacity in enumerate(capacities) if capacity), None)
    for delay in range(6):
        if active is not None:
            port, account = divmod(active, 5)
            yield edge(incoming=ReceivedBeat(Beat(port, channel, 2 if account == 4 else account, account == 4), 1))
            for _ in range(delay):
                yield edge(consumer=(port, account), consume=True)
        yield edge(ConnectionSignals(), reset=True)
        for _ in range(max(sum(capacities[port*5:port*5+5]) for port in range(ports))+20):
            yield edge()
    for _ in range(8):
        yield edge()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ports", type=int, default=1)
    parser.add_argument("--width", type=int, default=32)
    parser.add_argument("--credit-width", type=int, default=4)
    parser.add_argument("--capacity-hex", default="50132")
    parser.add_argument("--return-depth", type=int, default=4)
    parser.add_argument("--channel", choices=CHANNELS, default="req")
    args = parser.parse_args()
    value = int(args.capacity_hex, 16)
    if not 0 <= value < (1 << (args.ports*5*args.credit_width)):
        parser.error("capacity-hex does not fit the declared accounts")
    capacities = tuple((value >> (slot*args.credit_width)) & ((1 << args.credit_width)-1) for slot in range(args.ports*5))
    for row in vectors(args.ports, args.width, args.credit_width, capacities, args.return_depth, args.channel):
        print(" ".join(f"{value:x}" for value in row))


if __name__ == "__main__":
    main()

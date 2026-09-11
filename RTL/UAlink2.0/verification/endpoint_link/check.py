"""Independent source, TL/DL exactly-once, replay SRAM and receive retirement audit.
Run: python3 verification/endpoint_link/check.py RUN_DIRECTORY
Output: audit.json. Next: inspect coverage and rerun a fresh labeled case.
This reuses pre-existing independent TL semantic models, never RTL output classes.
"""
from collections import deque
from pathlib import Path
import argparse
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'model/tl'))
from credit_context import Context, decode_context
from receive_context import ReceiveContext


def need(condition, message):
    if not condition:
        raise ValueError(message)


def pack(values, width):
    return sum(v << (i * width) for i, v in enumerate(values))


def audit(directory):
    manifest = json.loads((directory / 'case.json').read_text())
    fixtures = manifest['fixtures']
    txctx = [Context(auth=bool(manifest['auth'])) for _ in range(2)]
    rxctx = [ReceiveContext(auth=bool(manifest['auth'])) for _ in range(2)]
    outstanding = [deque(), deque()]
    storage = [deque(), deque()]
    replay = [{}, {}]
    original_wire = [deque(), deque()]
    last_sequence = [511, 511]
    terminal = [None, None]
    completions = [0, 0]
    hi, di = [[0, 0], [0, 0]], [[0, 0], [0, 0]]
    returned, published = [[0] * 20 for _ in range(2)], [[0] * 20 for _ in range(2)]
    counts = dict(tx=0, delivered=0, retired=0, replay=0, crc_bad=0, dropped=0, fc=0, sequence_wraps=0)
    classes = dict(CONTROL=0, DATA=1, BYTE_ENABLE=2, NOP=3, MESSAGE=4, POISON=5, AUTH=6)
    mask = (1 << 256) - 1
    rows = (directory / 'trace.txt').read_text().splitlines()
    need(bool(rows), 'missing actual trace')
    for line in rows:
        fields = line.split()
        kind = fields[0]
        cycle, side, *v = [int(x, 16) for x in fields[1:]]
        prefix = f'{kind} side={side} cycle={cycle}: '
        if kind == 'T':
            msgbits, flit, ht, dt, ft, seq = v
            record = (msgbits << 512) | flit
            expected_sequence = 1 if last_sequence[side] == 511 else last_sequence[side] + 1
            need(seq == expected_sequence, prefix + 'independent nonzero DL sequence progression')
            counts['sequence_wraps'] += int(seq == 1 and counts['tx'] >= 511)
            last_sequence[side] = seq
            original_wire[side].append((seq, record))
            outstanding[side].append(record)
            replay[side][seq] = record
            messages = tuple((flit >> (j * 256)) & 255 if msgbits & (1 << j) else None for j in range(2))
            tokens = list(txctx[side].pending)
            head = None
            if len(tokens) <= 1 and messages[0] is None:
                decoded, appended, _ = decode_context(flit & mask)
                tokens.extend(appended)
                if decoded['fields']:
                    roles = {int(r['kind'] not in (1, 3)) for r in decoded['records']}
                    need(len(roles) == 1, prefix + 'mixed fixture header class')
                    head = roles.pop()
                    expected = fixtures[side][head]['headers']
                    need(hi[side][head] < len(expected) and flit & mask == int(expected[hi[side][head]], 16), prefix + 'source header order/data')
            observation = txctx[side].step(flit & mask, msg=messages)
            consumed = [0, 0]
            for j, classification in enumerate(observation['classes']):
                if classification == 'AUTH':
                    need(head is not None and (flit >> 256) == 0, prefix + 'fixture AuthTags')
                if classification in ('DATA', 'BYTE_ENABLE'):
                    token = tokens.pop(0)
                    owner = int(token.slot >= 15)
                    index = di[side][owner] + consumed[owner]
                    expected = fixtures[side][owner]['data']
                    need(index < len(expected) and (flit >> (j * 256)) & mask == int(expected[index], 16), prefix + 'source data ownership/order')
                    consumed[owner] += 1
            need(ht == (0 if head is None else 1 << head) and dt == pack(consumed, 2), prefix + 'source retirement is not atomic')
            if head is not None:
                hi[side][head] += 1
            di[side] = [a + b for a, b in zip(di[side], consumed)]
            if ft:
                counts['fc'] += 1
                if msgbits == 2:
                    need(flit == ((1 | (manifest['shared'] << 8)) << 256), prefix + 'initial completion format')
                    need(published[side] == manifest['capacities'], prefix + 'all initial credits precede completion')
                    completions[side] += 1
                else:
                    low = flit & mask
                    need(msgbits == 0 and 0 < low < 1 << 28, prefix + 'FC record')
                    for group, (position, width) in enumerate(((22, 3), (16, 3), (8, 5), (0, 5))):
                        field = (low >> position) & ((1 << (width + 3)) - 1)
                        lane = 1 + ((field >> width) & 3) if field & (1 << (width + 2)) else 0
                        slot = group * 5 + lane
                        published[side][slot] += field & ((1 << width) - 1)
                        need(published[side][slot] <= manifest['capacities'][slot] + returned[side][slot], prefix + 'credit published before SRAM retirement')
            counts['tx'] += 1
        elif kind == 'W':
            payload, is_replay, seq, header, data, drop, crc_ok = v
            if payload:
                need(seq in replay[side] and data == replay[side][seq], prefix + 'DL original/replay SRAM content')
                if not is_replay:
                    need(bool(original_wire[side]) and original_wire[side].popleft() == (seq, data), prefix + 'registered original SRAM output order')
                counts['replay'] += is_replay
            counts['dropped'] += drop
            counts['crc_bad'] += not crc_ok
        elif kind == 'D':
            data, port_taken, store_taken = v
            source = 1 - side
            need(port_taken == store_taken == 1, prefix + 'accepted DL payload rejected by TL')
            need(bool(outstanding[source]) and data == outstanding[source].popleft(), prefix + 'end-to-end missing/duplicate/corrupt TL payload')
            flit, msgbits = data & ((1 << 512) - 1), data >> 512
            messages = tuple((flit >> (j * 256)) & 255 if msgbits & (1 << j) else None for j in range(2))
            ob = rxctx[side].step(flit & mask, msg=messages)
            if ob['store']:
                word = pack(ob['releases'], 4) << 520 | pack([classes[c] for c in ob['classes']], 3) << 514 | data
                storage[side].append(word)
            counts['delivered'] += 1
        elif kind == 'S':
            word, = v
            need(bool(storage[side]) and storage[side].popleft() == word, prefix + 'actual 600-bit SRAM retirement')
            returned[side] = [x + ((word >> (520 + j * 4)) & 15) for j, x in enumerate(returned[side])]
            counts['retired'] += 1
        elif kind == 'Q':
            count, available, capacity, pending, unacked, scheduled = v
            need(count == len(storage[side]), prefix + 'receive SRAM occupancy')
            need(all(((available >> (j * 9)) & 511) <= ((capacity >> (j * 9)) & 511) for j in range(20)), prefix + 'credit overflow')
            need(unacked <= manifest['depth'] and scheduled <= unacked, prefix + 'DL replay window bounds')
            terminal[side] = (count, available, capacity, pending, unacked, scheduled)
        else:
            raise ValueError(prefix + 'unknown trace record')
    for side in range(2):
        need(completions[side] == 1, 'exactly one initialization completion')
        need(not original_wire[side], 'all original DL SRAM outputs must appear')
        count, available, capacity, pending, unacked, scheduled = terminal[side]
        need(count == pending == unacked == scheduled == 0 and available == capacity, 'terminal actual SRAM/replay/credit state')
        need(not outstanding[side] and not storage[side] and not txctx[side].pending and not rxctx[side].pending, 'all queues must drain')
        for role in range(2):
            need(hi[side][role] == len(fixtures[side][role]['headers']) and di[side][role] == len(fixtures[side][role]['data']), 'all source transactions must finish')
        need(published[side] == [c + r for c, r in zip(manifest['capacities'], returned[side])], 'terminal credit conservation')
    need(counts['tx'] == counts['delivered'] and counts['retired'] > 0, 'nonempty exactly-once transfer')
    if manifest['inject']:
        need(counts['replay'] > 0 and counts['crc_bad'] >= 2 and counts['dropped'] >= 2, 'required recovery fault coverage')
    return dict(passed=True, evidence_layer='integrated_rtl', counts=counts, headers=hi, data_halves=di, boundary='520-bit opaque local TL record; no DL wire framing/CRC computation/FEC')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    result = audit(args.directory)
    (args.directory / 'audit.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))

"""Ordered Common 2.0 credit metadata for the confirmed tenure profile.

The first half of each 64-byte pair reserves one credit (local interface policy).
Field legality beyond the existing tenure decoder is outside this model's scope.
"""
from copy import deepcopy
from dataclasses import dataclass

from tl_sequence import Sequencer
from tl_tenure import derive_control


@dataclass(frozen=True)
class Token:
    kind: str
    slot: int
    reserve: bool


def decode_context(word):
    decoded = derive_control(word)
    demands = [0] * 20
    tokens = []
    positions = {1: (116, 102), 2: (58, 46), 3: (55, 41),
                 4: (26, 14), 5: (26, 14)}
    for record in decoded['records']:
        kind = record['kind']
        value = word >> (record['sector'] * 32)
        vc_bit, pool_bit = positions[kind]
        vc, pool = (value >> vc_bit) & 3, (value >> pool_bit) & 1
        role = 0 if kind in (1, 3) else 1
        lane = 0 if pool else vc + 1
        demands[role * 5 + lane] += 1
        half = 0
        for token in record['tenure']:
            tokens.append(Token(token, 10 + role * 5 + lane,
                                token == 'D' and half % 2 == 0))
            if token == 'D':
                half += 1
        if half % 2:
            raise ValueError('unpaired field data tenure')
    return decoded, tuple(tokens), demands


class Context:
    def __init__(self, *, auth=False):
        self.sequence = Sequencer(auth=auth)
        self.pending = ()

    def step(self, lower=0, *, msg=(None, None), transfer=True, reset=False):
        if type(transfer) is not bool or type(reset) is not bool:
            raise TypeError('controls must be bool')
        if reset:
            self.sequence.step(reset=True)
            self.pending = ()
            return dict(classes=('RESET', 'RESET'), demands=(0,) * 20)
        if type(lower) is not int or not 0 <= lower < 1 << 256:
            raise ValueError('unsigned 256-bit lower required')
        if len(msg) != 2:
            raise ValueError('two half-flit message indicators required')
        proposal = deepcopy(self.sequence)
        queue = list(self.pending)
        demands = [0] * 20
        decoded = dict(fields=0, tenure=())
        if len(queue) <= 1 and msg[0] is None:
            decoded, appended, demands = decode_context(lower)
            queue.extend(appended)
        classes = proposal.step(msg=msg, fields=decoded['fields'],
                                tenure=decoded['tenure'])
        for category in classes:
            if category in ('DATA', 'POISON', 'BYTE_ENABLE'):
                token = queue.pop(0)
                expected = 'B' if category == 'BYTE_ENABLE' else 'D'
                if token.kind != expected:
                    raise ValueError('credit metadata and sequence disagree')
                if token.reserve:
                    demands[token.slot] += 1
        if tuple(token.kind for token in queue) != proposal.pending:
            raise ValueError('remaining metadata and sequence disagree')
        if transfer:
            self.pending = tuple(queue)
            self.sequence = proposal
        return dict(classes=classes, demands=tuple(demands))

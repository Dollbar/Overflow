"""Whole-tenure eligibility policy for the confirmed TL field profile.

Credits remain in the actual ledger until each wire transfer spends them. A sole
transmitter and mandatory ordered Data tenure prevent another header from taking
these credits before the admitted tenure finishes. Oversized candidates require
capacity-aware packing or a separately specified transaction policy.
"""
from credit_context import decode_context


def requirements(word, *, shared=False):
    _, tokens, commands = decode_context(word)
    result = list(commands)
    for token in tokens:
        if token.reserve:
            result[token.slot] += 1
    if shared:
        result[10] += result[15]
        result[15] = 0
    return tuple(result)


def admit(word, available, capacity, *, shared=False, done=True, control=True):
    if not control:
        return True, False, False
    need = requirements(word, shared=shared)
    shortfall = done and any(n > c for n, c in zip(need, capacity))
    allowed = not any(need) or (done and all(n <= a for n, a in zip(need, available)))
    return allowed, not allowed and not shortfall, shortfall

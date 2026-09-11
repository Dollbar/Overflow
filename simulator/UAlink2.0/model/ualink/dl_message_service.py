"""Conditional DL message service bounds, independent of RTL next-state cases.

L 200G DL/PL 2.0 section 2.4.1.2: two-level message round robin and at most
33 contiguous UART DWORDs. Bounds begin when a target head is continuously
eligible; source storage, cancellation, reset and loss of eligibility are outside
that interval. An opportunity is one actually supplied segment, not a clock.
No bound on replay/packing/CDC is invented by this module.
"""
from collections import deque
from dataclasses import dataclass
from functools import lru_cache

_GROUPS = ((0, 1, 2, 3, 4), (5, 6), (7, 8, 9, 10))
_LOCATION = {source: (group, local) for group, members in enumerate(_GROUPS)
             for local, source in enumerate(members)}
_RESET = (2, 4, 1, 3)  # Last-completed histories equivalent to reset next cursors.


@dataclass(frozen=True)
class ServiceStep:
    pending: int
    source: int
    words: int
    after: tuple[int, int, int, int]


@dataclass(frozen=True)
class ServiceBound:
    opportunities: int
    steps: tuple[ServiceStep, ...]


@dataclass(frozen=True)
class TimeBudget:
    completion_ps: int | None
    margin_ps: int | None
    meets_deadline: bool | None


def _integer(value, minimum, name):
    if type(value) is not int or value < minimum:
        raise ValueError(f'{name} must be an integer >= {minimum}')


def _history(history):
    if (type(history) is not tuple or len(history) != 4
            or any(type(v) is not int or not 0 <= v < limit
                   for v, limit in zip(history, (3, 5, 2, 4)))):
        raise ValueError('history must contain legal last-completed group/source indices')


def _target(target):
    _integer(target, 0, 'target')
    if target > 10:
        raise ValueError('target must be one of the eleven DL sources')


def _rank(history, source):
    group, local = _LOCATION[source]
    return ((group - history[0] - 1) % 3,
            (local - history[group + 1] - 1) % len(_GROUPS[group]))


def _advance(history, source):
    group, local = _LOCATION[source]
    after = list(history)
    after[0], after[group + 1] = group, local
    return tuple(after)


@lru_cache(maxsize=None)
def _bound(history, target):
    # Every winning source in any eligible set still wins after removing all
    # sources except itself and the persistent target. Thus eleven pairs cover
    # every one of the 1024 competing-source masks, including replenishment.
    best = ServiceBound(0, ())
    for source in range(11):
        if _rank(history, source) > _rank(history, target):
            continue
        after = _advance(history, source)
        cost = 33 if source == 7 else 1
        tail = ServiceBound(0, ()) if source == target else _bound(after, target)
        step = ServiceStep((1 << source) | (1 << target), source, cost, after)
        candidate = ServiceBound(cost + tail.opportunities, (step,) + tail.steps)
        if candidate.opportunities > best.opportunities:
            best = candidate
    return best


def service_bound(history, target):
    """Exact maximum opportunities to complete an eligible head from a boundary.

    Histories record the last completed group and the three local source indices.
    Arbitrary competing eligibility is allowed at each message boundary. UART
    competitors use their maximum legal length, which maximizes positive cost.
    The target transport also uses 33 words. An in-progress transport instead
    uses locked_service_bound. A source's messages behind its head are excluded.
    """
    _history(history)
    _target(target)
    return _bound(history, target)


@lru_cache(maxsize=1)
def _prefixes():
    prefixes = {_RESET: ()}
    queue = deque([_RESET])
    while queue:
        history = queue.popleft()
        for source in range(11):
            after = _advance(history, source)
            if after not in prefixes:
                prefixes[after] = prefixes[history] + (source,)
                queue.append(after)
    return prefixes


def reset_prefix(history):
    """Single-source complete messages reaching the requested history from reset."""
    _history(history)
    return _prefixes()[history]


def locked_service_bound(history, target, remaining):
    """Include 1..32 residual words of an already started legal UART transport.

    For target 7 the target is that active message itself, not a queued successor.
    All others wait until its last word, which updates both arbitration histories.
    """
    _history(history)
    _target(target)
    _integer(remaining, 1, 'remaining')
    if remaining > 32:
        raise ValueError('an already started transport has at most 32 remaining words')
    if target == 7:
        return remaining
    return remaining + _bound(_advance(history, 7), target).opportunities


def completion_budget(opportunities, *, first_ps, gap_ps, ingress_ps=0,
                      egress_ps=0, blackout_ps=0, deadline_ps=1_000_000):
    """Conditional completion bound in exact ps; None means no finite guarantee.

    ingress_ps includes prerequisite handling/queueing before continuous head
    eligibility; first_ps bounds its first service, gap_ps each following gap.
    blackout_ps is an additional TOTAL unavailable time over this response, not
    a per-replay-event allowance. egress_ps includes remaining transmit stages.
    Bounds must share consistent observation endpoints and not double count gaps.
    This evaluates a supplied service contract; it does not establish one.
    """
    for name, value, minimum in (('opportunities', opportunities, 1),
                                 ('ingress_ps', ingress_ps, 0), ('egress_ps', egress_ps, 0),
                                 ('deadline_ps', deadline_ps, 0)):
        _integer(value, minimum, name)
    for name, value, minimum in (('first_ps', first_ps, 0), ('gap_ps', gap_ps, 1),
                                 ('blackout_ps', blackout_ps, 0)):
        if value is not None:
            _integer(value, minimum, name)
    if first_ps is None or gap_ps is None or blackout_ps is None:
        return TimeBudget(None, None, None)
    elapsed = ingress_ps + first_ps + (opportunities - 1) * gap_ps + blackout_ps + egress_ps
    margin = deadline_ps - elapsed
    return TimeBudget(elapsed, margin, margin >= 0)

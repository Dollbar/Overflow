"""DL/PL 2.0 message arbitration over already eligible, staged DWORDs.

One tick represents one supplied segment opportunity, not a PHY clock. This
model does not encode messages, manage UART credits, or enforce time deadlines.
"""

from collections import deque
from dataclasses import dataclass


_GROUPS = ((0, (0, 1, 4, 5, 6)), (8, (0, 4)), (1, (0, 1, 6, 7)))
_SOURCES = tuple((group, kind) for group, kinds in _GROUPS for kind in kinds)


def _check_source(source: tuple[int, int]) -> None:
    if (type(source) is not tuple or len(source) != 2
            or any(type(part) is not int for part in source)
            or source not in _SOURCES):
        raise ValueError("source must be a defined DL message class/type pair")


@dataclass(frozen=True)
class Message:
    """An owned, immutable message; words include an opaque encoded header."""

    source: tuple[int, int]
    words: tuple[int, ...]
    tag: str = ""

    def __post_init__(self) -> None:
        _check_source(self.source)
        if not isinstance(self.words, (tuple, list)):
            raise ValueError("words must be a fully staged tuple or list of DWORDs")
        words = tuple(self.words)
        if any(type(word) is not int or not 0 <= word < (1 << 32) for word in words):
            raise ValueError("each word must be an unsigned 32-bit integer")
        if self.source == (1, 0):
            if not 2 <= len(words) <= 33:
                raise ValueError("UART transport requires a header and 1..32 payload DWORDs")
        elif len(words) != 1:
            raise ValueError("non-transport messages contain exactly one DWORD")
        object.__setattr__(self, "words", words)


@dataclass(frozen=True)
class MessageBeat:
    """A serviced DWORD with local observation metadata, not new wire fields."""

    source: tuple[int, int]
    word: int
    index: int
    last: bool
    tag: str


class DLMessageArbiter:
    """Bounded per-source FIFOs and two-level round robin with message locking.

    An active message stays at its source FIFO head until the last DWORD is
    serviced, so queue_depth includes it. Both round-robin cursors advance
    only at message completion. Initial priorities are implementation choices.
    """

    def __init__(self, queue_depth: int = 2):
        if type(queue_depth) is not int or queue_depth < 1:
            raise ValueError("queue_depth must be a positive integer")
        self._depth = queue_depth
        self._queues = {source: deque() for source in _SOURCES}
        self._group_next = 0
        self._local_next = [0] * len(_GROUPS)
        self._active: tuple[int, int] | None = None
        self._word_index = 0

    def offer(self, message: Message) -> bool:
        """Queue a complete eligible message; a full source leaves all state intact."""
        if not isinstance(message, Message):
            raise ValueError("offer requires a validated Message")
        queue = self._queues[message.source]
        if len(queue) >= self._depth:
            return False
        queue.append(message)
        return True

    def pending(self, source: tuple[int, int] | None = None) -> int:
        """Count messages, including a partially transmitted message."""
        if source is None:
            return sum(len(queue) for queue in self._queues.values())
        _check_source(source)
        return len(self._queues[source])

    def tick(self, segment_available: bool = True, reset: bool = False) -> MessageBeat | None:
        """Service at most one DWORD, or synchronously reset local model state."""
        if type(segment_available) is not bool or type(reset) is not bool:
            raise ValueError("segment_available and reset must be booleans")
        if reset:
            for queue in self._queues.values():
                queue.clear()
            self._group_next = 0
            self._local_next = [0] * len(_GROUPS)
            self._active = None
            self._word_index = 0
            return None
        if not segment_available:
            return None
        if self._active is None:
            self._active = self._select()
            if self._active is None:
                return None
        group_index, local_index = self._active
        group, kinds = _GROUPS[group_index]
        source = (group, kinds[local_index])
        message = self._queues[source][0]
        index = self._word_index
        last = index + 1 == len(message.words)
        beat = MessageBeat(source, message.words[index], index, last, message.tag)
        if last:
            self._queues[source].popleft()
            self._local_next[group_index] = (local_index + 1) % len(kinds)
            self._group_next = (group_index + 1) % len(_GROUPS)
            self._active = None
            self._word_index = 0
        else:
            self._word_index += 1
        return beat

    def _select(self) -> tuple[int, int] | None:
        """Find a pending group, then its pending source, in circular priority order."""
        for distance in range(len(_GROUPS)):
            group_index = (self._group_next + distance) % len(_GROUPS)
            group, kinds = _GROUPS[group_index]
            for local_distance in range(len(kinds)):
                local_index = (self._local_next[group_index] + local_distance) % len(kinds)
                if self._queues[(group, kinds[local_index])]:
                    return group_index, local_index
        return None

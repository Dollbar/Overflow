"""Synchronous SRAM-backed FIFO reference with a two-word output reservation.

The reference uses deques, not SRAM addresses or RTL pointers. Values in the
read pipeline and output cache still consume the exact logical FIFO capacity.
"""

from collections import deque
from dataclasses import dataclass


@dataclass(frozen=True)
class FifoView:
    ready: bool
    valid: bool
    data: int
    count: int


@dataclass(frozen=True)
class FifoStep:
    accepted: bool = False
    consumed: int | None = None


class ReceiveFifo:
    def __init__(self, depth, width=32):
        if type(depth) is not int or type(width) is not int:
            raise TypeError("depth and width must be integers")
        if not 1 <= depth <= 65535 or width <= 0 or width % 8:
            raise ValueError("depth must be 1..65535 and width a positive byte multiple")
        self.depth, self.width = depth, width
        self._unread, self._visible, self._pending = deque(), deque(), None

    @property
    def outputs(self):
        count = len(self._unread) + len(self._visible) + int(self._pending is not None)
        return FifoView(count < self.depth, bool(self._visible), self._visible[0] if self._visible else 0, count)

    def step(self, data=None, consume=False, reset=False):
        if type(reset) is not bool:
            raise TypeError("reset must be boolean")
        if reset:
            self._unread, self._visible, self._pending = deque(), deque(), None
            return FifoStep()
        if type(consume) is not bool or (data is not None and type(data) is not int):
            raise TypeError("consume must be boolean and data an integer or None")
        if data is not None and not 0 <= data < (1 << self.width):
            raise ValueError("data does not fit the declared byte width")
        before = self.outputs
        accepted = data is not None and before.ready
        pop = consume and before.valid
        room = len(self._visible) + int(self._pending is not None) - int(pop) < 2
        read_result = self._unread.popleft() if self._unread and room else None
        consumed = self._visible.popleft() if pop else None
        if self._pending is not None:
            self._visible.append(self._pending)
        self._pending = read_result
        if accepted:
            self._unread.append(data)
        return FifoStep(accepted, consumed)

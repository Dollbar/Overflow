"""Abstract ordered half-Flit queue; intentionally independent of SRAM latency/banking."""
from collections import deque
class HalfQueue:
    def __init__(self,bank_depth):
        if not 1<=bank_depth<=65535:raise ValueError('bank depth')
        self.capacity=2*bank_depth;self.words=deque()
    @property
    def count(self):return len(self.words)
    def reset(self):self.words.clear()
    def push(self,words):
        if len(words) not in (1,2) or self.count+len(words)>self.capacity:return False
        self.words.extend(words);return True
    def offer(self,words):
        if len(words) not in (1,2):return 0
        n=min(len(words),self.capacity-self.count);self.words.extend(words[:n]);return n
    def pop(self,n):
        if n not in (0,1,2) or n>self.count:return []
        return [self.words.popleft() for _ in range(n)]

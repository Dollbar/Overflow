"""One owned Control group; independent sequence oracle, not RTL metadata math.

step() returns pre-edge observations and then applies the edge. Capacity belongs
to the captured initialization epoch. Reset cancels ownership, including errors.
"""
from control_partition import choose


class PreparedPartitioner:
    def __init__(self):
        self.owned = None
        self.cursor = 0

    def step(self, word, tags, capacity, *, valid=True, ready=True, done=True,
             reset=False, response=False, auth=False, shared=False):
        out = dict(valid=False, error=False, shortfall=False, word=0, tags=0, fields=0, end=0)
        if self.owned is not None and not reset:
            w, t, c, attributes = self.owned
            out = choose(w, t, c, cursor=self.cursor, **attributes)
        out['cursor'] = 0 if reset else self.cursor
        out['taken'] = bool(out['valid'] and ready)
        out['group_done'] = bool(out['taken'] and out['end'] == 8)
        out['source_ready'] = bool(not reset and done and (self.owned is None or out['group_done']))
        out['captured'] = bool(valid and out['source_ready'])
        if reset:
            self.owned = None
            self.cursor = 0
        else:
            if out['taken']:
                self.cursor = 0 if out['group_done'] else out['end']
            if out['group_done']:
                self.owned = None
            if out['captured']:
                self.owned = (word, tags, tuple(capacity), dict(response=response, auth=auth, shared=shared))
        return out

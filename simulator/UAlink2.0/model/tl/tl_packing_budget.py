"""Common2.0 §5.7 TL packing budget, at committed logical-Flit granularity.

Not a TL wire encoder or a VC/data-pool credit implementation. A rejected proposal
must never be transmitted. DL replay is not another logical TL commit.
"""
class PackingBudget:
    def __init__(self):
        self._requests=0
        self._responses=0

    @property
    def available(self):
        return 4-self._requests,8-self._responses

    def step(self,requests=0,responses=0,*,transfer=False,reset=False):
        for value,limit in ((requests,8),(responses,16)):
            if type(value) is not int:raise TypeError('count must be an integer')
            if not 0<=value<limit:raise ValueError('count outside local encoded width')
        if type(transfer) is not bool or type(reset) is not bool:raise TypeError('controls must be boolean')
        if reset:
            self._requests=self._responses=0
            return False
        req_limit,rsp_limit=self.available
        if not transfer or requests>req_limit or responses>rsp_limit:return False
        self._requests=max(0,self._requests+requests-1)
        self._responses=max(0,self._responses+responses-1)
        return True

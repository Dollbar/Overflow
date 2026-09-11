"""Partition independent prepared fields without changing field bits or Data tenure.
Only total initialized capacity is used here; actual credit balances remain downstream.
"""
from tl_tenure import derive_control
from credit_admission import requirements

def choose(word,tags,capacity,*,cursor=0,response=False,auth=False,shared=False):
    out=dict(valid=False,error=False,shortfall=False,word=0,tags=0,fields=0,end=0)
    try:
        dec=derive_control(word);records=dec['records'];sizes={1:4,2:2,3:2,4:1,5:1};occupied=0
        if not records or not 0<=cursor<8:raise ValueError('empty or invalid source cursor')
        for record in records:
            if (record['kind'] not in (1,3))!=response:raise ValueError('wrong queue class')
            occupied|=((1<<(32*sizes[record['kind']]))-1)<<(32*record['sector'])
        if word&~occupied:raise ValueError('source may contain NOP padding but not FC events')
        before=sum(r['sector']<cursor for r in records)
        for end in range(cursor+1,9):
            if any(r['sector']<end<r['sector']+sizes[r['kind']] for r in records):continue
            selected=[r for r in records if cursor<=r['sector']<end]
            if not selected or (auth and len(selected)>4):continue
            prefix=word&(((1<<(32*end))-1)^((1<<(32*cursor))-1))
            if all(n<=c for n,c in zip(requirements(prefix,shared=shared),capacity)):
                out.update(valid=True,word=prefix,tags=((tags>>(64*before))&((1<<(64*len(selected)))-1)) if auth else 0,fields=len(selected),end=end)
        out['shortfall']=not out['valid']
    except ValueError:out['error']=True
    return out

class Partitioner:
    def __init__(self):self.cursor=0
    def step(self,word,tags,capacity,*,valid=True,ready=True,done=True,reset=False,**kw):
        out=choose(word,tags,capacity,cursor=self.cursor,**kw)
        if reset or not valid:out=dict(valid=False,error=False,shortfall=False,word=0,tags=0,fields=0,end=0)
        elif not done:out.update(valid=False,shortfall=False,word=0,tags=0,fields=0,end=0)
        out['cursor']=0 if reset else self.cursor;out['taken']=bool(out['valid'] and ready);out['source_taken']=bool(out['taken'] and out['end']==8)
        if reset:self.cursor=0
        elif out['taken']:self.cursor=0 if out['source_taken'] else out['end']
        return out

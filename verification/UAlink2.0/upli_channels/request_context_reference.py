"""Independent local ownership model; network Tag is copied, never allocated here.
Run through run.py. Output vectors contain full descriptor expectations before each edge.
This is a bounded generation token, not an unbounded anti-ABA or link epoch protocol.
"""
from dataclasses import dataclass
from collections import deque
from random import Random
@dataclass(frozen=True)
class Descriptor:
    station:int;port:int;vc:int;pool:int;payload:int;data:int;be:int;poison:int;pools:int
    @property
    def tag(self):return (self.payload>>87)&2047
    @property
    def key(self):return self.station,self.port,self.tag
    def values(self):return [self.station,self.port,self.vc,self.pool,self.payload,self.data,self.be,self.poison,self.pools]
ZERO=Descriptor(*([0]*9))
class Context:
    def __init__(self,capacity,ports,genbits=8):
        self.capacity=capacity;self.ports=ports;self.genbits=genbits;self.slotbits=max(1,(capacity-1).bit_length());self.reset()
    def reset(self):
        self.entries={};self.pending=deque();self.generations=[0]*self.capacity
    def inspect(self,rstn,valid,d,issue_ready,release_valid,release_token):
        if not rstn:return [0]*16
        used={v['d'].key for v in self.entries.values()}
        bad=d.port>=self.ports or d.key in used
        free=next((i for i in range(self.capacity) if i not in self.entries),None)
        ready=not bad and free is not None
        gen=((self.generations[free]+1)&((1<<self.genbits)-1)) if free is not None else 0
        alloc_token=((gen<<self.slotbits)|free) if ready and valid else 0
        iv=bool(self.pending);slot=self.pending[0] if iv else 0
        item=self.entries[slot] if iv else None
        token=item['token'] if iv else 0;out=item['d'] if iv else ZERO
        relslot=release_token&((1<<self.slotbits)-1)
        rel=self.entries.get(relslot)
        rr=bool(rel and rel['issued'] and rel['token']==release_token)
        error=(bool(valid) and bad) or (bool(release_valid) and not rr)
        return [int(ready),alloc_token,int(iv),token,*out.values(),int(rr),len(self.entries),int(error)]
    def edge(self,rstn,valid,d,issue_ready,release_valid,release_token):
        out=self.inspect(rstn,valid,d,issue_ready,release_valid,release_token)
        if not rstn:self.reset();return out
        if out[2] and issue_ready:
            slot=self.pending.popleft();self.entries[slot]['issued']=True
        if release_valid and out[13]:del self.entries[release_token&((1<<self.slotbits)-1)]
        if valid and out[0]:
            token=out[1];slot=token&((1<<self.slotbits)-1)
            self.generations[slot]=token>>self.slotbits;self.entries[slot]={'d':d,'token':token,'issued':False};self.pending.append(slot)
        return out

def descriptor(seed,ports,tag=None,station=None):
    r=Random(0x918238+seed);t=(1024+seed)%2048 if tag is None else tag
    # Request Tag at [97:87], all other fields independent dense source bits.
    payload=(r.getrandbits(184)&~(2047<<87))|(t<<87)
    return Descriptor((128+seed)%256 if station is None else station,seed%ports,seed%4,(seed//4)%2,payload,r.getrandbits(2048),r.getrandbits(256),seed%16,(seed*3)%16)

def vectors(path,capacity,ports):
    m=Context(capacity,ports);rows=[];allocations=0;issues=0;releases=0;errors=0;stall=0
    def put(rstn=1,valid=0,d=ZERO,ready=0,rv=0,token=0):
        nonlocal allocations,issues,releases,errors,stall
        out=m.edge(rstn,valid,d,ready,rv,token)
        rows.append([rstn,valid,*d.values(),ready,rv,token,*out])
        allocations+=bool(valid and out[0]);issues+=bool(ready and out[2]);releases+=bool(rv and out[13]);errors+=out[-1];stall+=bool(out[2] and not ready)
        return out
    put(rstn=0);put(rstn=0);put()
    originals=[];tokens=[]
    for i in range(capacity):
        d=descriptor(i,ports);originals.append(d);tokens.append(put(valid=1,d=d)[1])
    # Fullness is benign backpressure; no implicit use of a future release.
    for _ in range(7):put(valid=1,d=descriptor(70,ports))
    for d in originals:
        changed=Descriptor(d.station,d.port,d.vc^3,d.pool^1,d.payload^(1<<117)^(1<<22),d.data^1,d.be^1,d.poison^1,d.pools^1)
        put(valid=1,d=changed)
    put(rv=1,token=tokens[0]) # queued but not issued: reject
    for _ in range(19):put()
    for token in tokens:
        put(ready=1,rv=1,token=token) # newly issuing is not already issued
    # Reverse release order proves completion order is separate from issue order.
    for token in reversed(tokens):put(rv=1,token=token)
    put(rv=1,token=tokens[0]);put()
    # Same network Tag reuses a local slot with a new token; stale release rejected.
    old=tokens[0];new=put(valid=1,d=originals[0])[1];put(ready=1);put(rv=1,token=old);put(rv=1,token=new)
    # Same port/tag in different station is distinct; same tag across ports is distinct.
    group=[]
    for station,port,tag in [(3,0,2047),(131,0,2047),(3,0,1023)]+([(3,1,2047)] if ports>1 else []):
        base=descriptor(83,ports,tag=tag,station=station);d=Descriptor(station,port,*base.values()[2:])
        out=put(valid=1,d=d)
        if out[0]:group.append(out[1])
    for _ in group:put(ready=1)
    for token in group:put(rv=1,token=token)
    if ports<4:
        d=descriptor(95,ports);put(valid=1,d=Descriptor(d.station,ports,*d.values()[2:]));put(valid=0,d=Descriptor(d.station,3,*d.values()[2:]))
    # Random interleavings inspect only independent public stimuli/state model.
    rng=Random(0x439+ports+capacity);seq=200
    for _ in range(220):
        live=list(m.entries.values());d=descriptor(seq,ports);seq+=1
        if live and rng.randrange(5)==0:d=rng.choice(live)['d']
        rv=int(bool(live) and rng.randrange(3)==0)
        rt=rng.choice(live)['token'] if rv else 0
        put(valid=int(rng.randrange(3)!=0),d=d,ready=int(rng.randrange(3)==0),rv=rv,token=rt)
    while m.pending:put(ready=1)
    for item in list(m.entries.values()):put(rv=1,token=item['token'])
    # Reset cancels both queued and issued state; same Tag accepted in next epoch.
    t=put(valid=1,d=originals[0])[1];put();put(rstn=0);put(rv=1,token=t)
    t=put(valid=1,d=originals[0])[1];put(ready=1);put(rstn=0);put(rv=1,token=t);put()
    path.write_text(''.join(' '.join(format(v,'x') for v in row)+'\n' for row in rows))
    return {'rows':len(rows),'allocations':allocations,'issues':issues,'releases':releases,'rejected_events':errors,'issue_stall_rows':stall,'columns':30}

def bridge_vectors(path):
    rows=[]
    for i in range(8):
        n=0 if i%3==0 else i%4+1
        command=3 if n==0 else (0x29 if i%2 else 0x28)
        length=63 if n==0 else n*16-1
        address=(1<<56)|0x120000|(i<<8)
        tag=1024+i*17;src=777;dst=999;auth=(1<<63)|0x10203|i
        request=(i^0x5a)|(0xa5<<8)|(length<<16)|(command<<22)|(address<<28)|((max(n,1)-1)<<85)|(tag<<87)|(dst<<98)|(src<<108)|(auth<<118)|(2<<182)
        data=be=poison=pools=0
        for beat in range(n):
            for lane in range(64):data|=((i*31+beat*19+lane*7+1)&255)<<(beat*512+lane*8)
            be|=(0xa55af0ffcc338001^(i<<beat))<<(beat*64)
            poison|=int(beat==1)<<beat;pools|=((i+beat)&1)<<beat
        rows.append([request,n,data,be,poison,pools])
    path.write_text(''.join(' '.join(format(v,'x') for v in row)+'\n' for row in rows))
    return {'rows':len(rows),'widths':[184,3,2048,256,4,4],'scope':'trusted ordered head BFM -> real request bridge -> real context table; no SRAM/credit-return claim'}

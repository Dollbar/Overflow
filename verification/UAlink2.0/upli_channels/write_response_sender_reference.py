"""Independent integer-account and native event reference; no RTL/model helper imports."""
from dataclasses import dataclass
from random import Random


def pack(fields):
    value=0
    for word,width in fields:
        if not 0<=word<(1<<width):raise ValueError('field width')
        value=(value<<width)|word
    return value


@dataclass(frozen=True)
class Candidate:
    port:int
    vc:int
    pool:bool
    payload:int


class Reference:
    def __init__(self,ports,width,init_cycles,capacities):
        self.ports,self.width,self.init_cycles=ports,width,init_cycles
        self.capacity=list(capacities)
        self.balance=[0]*(ports*5)
        self.confirmed=[False]*ports
        self.consecutive=[0]*ports
        self.phase=None
        self.error=False
        self.sticky=False
        self.rows=[]
        self.coverage={key:0 for key in ('accepted','blocked_credit','blocked_phase','blocked_init','blocked_connection','idle_phase_advance','simultaneous_return_send','resets','high_tag','high_auth','nonzero_status','returns','pool_sends','vc_sends','candidate_held','diagnostic_edges','blocked_unused_port')}

    def state(self):
        balance=sum(value<<(index*self.width) for index,value in enumerate(self.balance))
        init=sum(int(v)<<p for p,v in enumerate(self.confirmed))
        return pack([(balance,self.ports*5*self.width),(init,4),(int(self.phase is not None),1),(self.phase or 0,2),(int(self.error),1),(int(self.sticky),1)])

    def step(self,candidate=None,*,rstn=True,credit_connected=True,beats_connected=True,returns=(),done=0,noise=None):
        before=self.state()
        c=candidate or noise or Candidate(0,0,False,0)
        active=candidate is not None
        valid_port=0<=c.port<self.ports
        account=c.port*5+(4 if c.pool else c.vc)
        initialized=valid_port and self.confirmed[c.port]
        credited=valid_port and self.balance[account]>0
        slot=self.phase is None or self.phase==c.port
        send=bool(rstn and credit_connected and beats_connected and active and valid_port and initialized and credited and slot)
        cv=cp=vcs=nums=0
        for p,vc,pool,number in returns:
            if cv&(1<<p):raise ValueError('duplicate return port')
            if not 1<=number<=4:raise ValueError('credit encoding')
            cv|=1<<p;cp|=int(pool)<<p;vcs|=vc<<(2*p);nums|=(number-1)<<(2*p)
        stimulus=pack([(int(rstn),1),(int(credit_connected),1),(int(beats_connected),1),(int(active),1),(c.port,2),(c.vc,2),(int(c.pool),1),(c.payload,101),(cv,4),(cp,4),(vcs,8),(nums,8),(done,4)])
        native=[0]*10
        if send:
            # Decode using independently documented fixed bit positions, not DUT outputs.
            payload=c.payload
            auth=(payload>>37)&((1<<64)-1);typ=(payload>>35)&3;tag=(payload>>24)&2047
            status=(payload>>20)&15;src=(payload>>10)&1023;dst=payload&1023
            native=[1,typ,tag,status,src,dst,c.port,c.vc,int(c.pool),auth]
            self.coverage['accepted']+=1
            self.coverage['high_tag']+=bool(tag&1024)
            self.coverage['high_auth']+=bool(auth&(1<<63))
            self.coverage['nonzero_status']+=status!=0
            self.coverage['pool_sends' if c.pool else 'vc_sends']+=1
        cpbit=sum(v.bit_count() for v in native[1:9])%2
        expected=pack([(int(send),1)]+list(zip(native,(1,2,11,4,10,10,2,2,1,64)))+[(int(send),1),(native[9].bit_count()%2,1),(cpbit,1)])
        if not rstn:
            self.balance=[0]*(self.ports*5);self.confirmed=[False]*self.ports;self.consecutive=[0]*self.ports;self.phase=None;self.error=self.sticky=False
            self.coverage['resets']+=1
        else:
            if active and not send:
                self.coverage['candidate_held']+=1
                self.coverage['blocked_unused_port']+=not valid_port
                self.coverage['blocked_credit']+=not credited
                self.coverage['blocked_init']+=not initialized
                self.coverage['blocked_phase']+=not slot
                self.coverage['blocked_connection']+=not(credit_connected and beats_connected)
            if self.phase is not None:
                self.coverage['idle_phase_advance']+=not send
                self.phase=(self.phase+1)%self.ports
            elif send:self.phase=(c.port+1)%self.ports
            next_balance=self.balance.copy();bad=False
            for p in range(4):
                if p>=self.ports:
                    bad|=bool((cv|done)&(1<<p))
                elif not self.confirmed[p] and (done&(1<<p)) and not credit_connected:bad=True
            for p,vc,pool,number in returns:
                self.coverage['returns']+=number
                if p>=self.ports or not credit_connected:bad=True;continue
                next_balance[p*5+(4 if pool else vc)]+=number
            if send:next_balance[account]-=1
            bad|=any(b<0 or b>cap for b,cap in zip(next_balance,self.capacity))
            if not bad:
                self.balance=next_balance
                for p in range(self.ports):
                    if self.confirmed[p]:continue
                    self.consecutive[p]=self.consecutive[p]+1 if done&(1<<p) else 0
                    if self.consecutive[p]>=self.init_cycles:self.confirmed[p]=True
            self.error=bool(bad);self.sticky|=bad
            self.coverage['diagnostic_edges']+=bad
            self.coverage['simultaneous_return_send']+=send and bool(returns)
        self.rows.append((stimulus,expected,before,self.state()))
        return send


def generate(path,ports,width,init_cycles,capacities):
    ref=Reference(ports,width,init_cycles,capacities)
    rng=Random(0x57525345+ports*100+width*10+init_cycles)
    done=(1<<ports)-1
    serial=0
    def candidate(port=None,vc=None,pool=None,payload=None):
        nonlocal serial
        serial+=1
        # Distinct high-bit identities and all 101 payload bits can change after retirement.
        return Candidate(rng.randrange(ports) if port is None else port,rng.randrange(4) if vc is None else vc,bool(rng.randrange(2)) if pool is None else pool,rng.getrandbits(101) if payload is None else payload)
    def reset():ref.step(rstn=False);ref.step(rstn=False,noise=candidate())
    def refill(pairs=None):
        # Return at most four per port per cycle; filling does not read hardware.
        while True:
            returns=[]
            for p in range(ports):
                options=range(5) if pairs is None else [a for pp,a in pairs if pp==p]
                for a in options:
                    missing=capacities[p*5+a]-ref.balance[p*5+a]
                    if missing:
                        returns.append((p,0 if a==4 else a,a==4,min(4,missing)));break
            if not returns:break
            ref.step(returns=returns,done=done if all(ref.confirmed) else 0)
    def bootstrap():
        reset()
        ref.step(credit_connected=False,beats_connected=False,noise=candidate())
        refill()
        for _ in range(init_cycles-1):ref.step(done=done)
        ref.step(done=0) # A short high pulse cannot complete initialization.
        for _ in range(init_cycles):ref.step(done=done)
    bootstrap()
    if ports<4:
        invalid=Candidate(ports,2,False,(1<<101)-1)
        for _ in range(ports+2):
            if ref.step(invalid,done=done):raise AssertionError('unused port accepted')
        bootstrap() # Common reset explicitly cancels this unacceptably routed candidate.
    # Reject connection qualification even with balances and initialization complete.
    first=candidate(ports-1,0,False,(1<<101)-1)
    if capacities[(ports-1)*5]==0:first=candidate(ports-1,0,True,(1<<101)-1)
    ref.step(first,credit_connected=False,beats_connected=False,done=0)
    ref.step(first,beats_connected=False,done=done)
    if not ref.step(first,done=done):raise AssertionError('directed first send')
    for _ in range(ports*3):ref.step(noise=candidate(),done=done)
    # All account/port paths, including a configured zero-capacity lane (diagnostic stall only).
    for p in range(ports):
        for a in range(5):
            if capacities[p*5+a]==0:
                ref.step(candidate(p,a,False),done=done);bootstrap();continue
            refill([(p,a)])
            c=candidate(p,3 if a==4 else a,a==4)
            while not ref.step(c,done=done):pass
    # Exhaust one known nonzero account; a return on its empty edge cannot bypass.
    p=ports-1;a=4
    c=candidate(p,3,True)
    while ref.balance[p*5+a]>0:ref.step(c,done=done)
    for _ in range(ports*2):ref.step(c,done=done)
    while ref.phase!=p:ref.step(c,done=done)
    if ref.step(c,returns=[(p,3,True,1)],done=done):raise AssertionError('new return bypassed')
    while not ref.step(c,done=done):pass
    # Candidate held from last init sample through the first eligible subsequent edge.
    reset();refill()
    c=candidate(ports-1,3,True)
    for _ in range(init_cycles):
        if ref.step(c,done=done):raise AssertionError('new init bypassed')
    if not ref.step(c,done=done):raise AssertionError('initialized send absent')
    # Independent waiting candidate never changes while active; idle noise is unconstrained.
    pending=None
    for cycle in range(900):
        if pending is None and cycle%5:
            pending=candidate()
            while capacities[pending.port*5+(4 if pending.pool else pending.vc)]==0:pending=candidate()
        returns=[]
        for p in range(ports):
            a=(cycle+p)%5;missing=capacities[p*5+a]-ref.balance[p*5+a]
            if missing:returns.append((p,rng.randrange(4) if a==4 else a,a==4,min(4,missing)))
        sent=ref.step(pending,returns=returns,done=done,noise=candidate())
        if sent:pending=None
    while pending:
        account=pending.port*5+(4 if pending.pool else pending.vc)
        returns=[] if ref.balance[account] else [(pending.port,pending.vc,pending.pool,1)]
        if ref.step(pending,returns=returns,done=done):pending=None
    # 101 distinct walking bits make high Tag/Auth and low ID paths observable.
    for bit in range(101):
        refill([(ports-1,4)])
        c=candidate(ports-1,bit%4,True,1<<bit)
        while not ref.step(c,done=done):pass
    # Invalid returns are isolated idle diagnostic checks, not a recovery claim.
    reset();refill()
    for _ in range(init_cycles):ref.step(done=done)
    ref.step(returns=[(0,0,True,1)],done=done)
    ref.step(done=done)
    if ports<4:ref.step(returns=[(ports,1,False,1)],done=done)
    reset()
    ref.step(noise=candidate(),credit_connected=False,beats_connected=False)
    with path.open('w') as out:
        for row in ref.rows:out.write(' '.join(f'{v:x}' for v in row)+'\n')
    return {'rows':len(ref.rows),'coverage':ref.coverage,'capacities':capacities,'seed':0x57525345+ports*100+width*10+init_cycles}

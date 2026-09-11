"""Independent set-based role Drop/notification model; no HDL or existing model imports."""
import random

def generate(path,ports,roles,tl):
    if ports not in (1,2,4) or roles not in (1,2) or tl not in (0,1) or (tl and roles!=2):raise ValueError('configuration')
    history=set();dropped=set();acked=set();incomplete=set();rows=[]
    def owner(channel):return 0 if roles==1 or channel in (1,2) else 1
    def affected(events):
        found={(1-owner(channel)) if category==1 and roles==2 else owner(channel) for category,channel in events}
        return set(range(roles)) if tl and found else found
    def pack(items):return sum(1<<item for item in items)
    def output(rstn,ack,events,data):
        fresh=affected(events-history)
        visible=dropped|affected(events) if rstn else set()
        pending=(visible-acked)|fresh if rstn else set()
        accepted={r for r in dropped if ack>>r&1 and r not in fresh} if rstn else set()
        portbits=sum(1<<(r*ports+p) for r in visible for p in range(ports))
        reasons=sum(1<<(category*4+channel) for category,channel in history)
        return pack(visible),portbits,pack(pending),pack(accepted),pack(visible),reasons,pack(incomplete),data if rstn else 0
    def add(rstn=1,ack=0,init=None,errors=None,data=0):
        nonlocal history,dropped,acked,incomplete
        init=((1<<roles)-1) if init is None else init
        errors=errors or [0]*8
        events={(category,ch) for category,word in enumerate(errors) for ch in range(4) if word>>ch&1}
        pre=output(rstn,ack,events,data)
        if not rstn:history=set();dropped=set();acked=set();incomplete=set()
        else:
            incoming=affected(events);fresh=affected(events-history)
            incomplete|={r for r in incoming-dropped if not(init>>r&1)}
            acked|={r for r in dropped if ack>>r&1}
            acked-=fresh
            dropped|=incoming;history|=events
        post=output(rstn,ack,events,data)
        rows.append((rstn,ack,init,*errors,data,*pre,*post))
    add(rstn=0,data=15,errors=[15]*8)
    for category in range(8):
        for ch in range(4):
            add(rstn=0)
            add(ack=(1<<roles)-1,data=15)
            error=[0]*8;error[category]=1<<ch
            add(ack=(1<<roles)-1,init=0,errors=error,data=10)
            add(ack=(1<<roles)-1)
            for _ in range(3):add()
            # A new error category after acknowledgement requests a fresh notification.
            error[(category+1)%8]|=1<<((ch+1)%4)
            add(errors=error)
            add(ack=(1<<roles)-1,errors=error)
            add()
    for mask in range(16):
        add(rstn=0);add(data=mask);add(ack=(1<<roles)-1,data=mask)
    rng=random.Random(0xD20F+ports+roles*7+tl*19)
    for k in range(1800):
        errors=[0]*8
        if rng.randrange(3)==0:errors[rng.randrange(8)]=rng.randrange(16)
        add(rstn=int(k%31!=0),ack=rng.randrange(1<<roles),init=rng.randrange(1<<roles),errors=errors,data=rng.randrange(16))
    add(rstn=0,ack=(1<<roles)-1,errors=[15]*8)
    path.write_text(''.join(' '.join(f'{word:x}' for word in row)+'\n' for row in rows))
    return {'rows':len(rows),'ports':ports,'roles':roles,'is_tl':tl,'directed_error_sources':32,'data_only_masks':16}

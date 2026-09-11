"""Independent bit-set parity oracle for packed native RX records; no RTL/model imports."""
import random
WIDTHS=(184,619,101,580)
def parity(n):
    out=0
    while n:
        out ^= n & 1
        n >>= 1
    return out

def bitrange(n,low,width):return (n>>low)&((1<<width)-1)

def protect(kind,payload,port,vc,pool,valid):
    if kind==0:
        auth=bitrange(payload,118,64);address=bitrange(payload,28,57);data=be=0
        # Control parity is XOR of the disjoint native fields, independent of concatenation order.
        fields=[bitrange(payload,182,2),bitrange(payload,87,11),bitrange(payload,16,6),bitrange(payload,8,8),bitrange(payload,22,6),bitrange(payload,0,8),bitrange(payload,108,10),bitrange(payload,98,10),bitrange(payload,85,2)]
    elif kind==1:
        auth=bitrange(payload,555,64);address=be=0;data=bitrange(payload,10,512)
        fields=[bitrange(payload,545,10),bitrange(payload,535,10),bitrange(payload,524,11),bitrange(payload,522,2),bitrange(payload,0,10)]
    elif kind==2:
        auth=bitrange(payload,37,64);address=data=be=0
        fields=[bitrange(payload,0,37)]
    else:
        auth=address=0;data=bitrange(payload,68,512);be=bitrange(payload,4,64)
        fields=[bitrange(payload,0,4)]
    control=parity(port)^parity(vc)^pool
    for field in fields:control ^= parity(field)
    code=valid|(control<<1)
    mask=1
    if valid:mask |= 2
    if kind==0:
        code |= parity(address)<<2
        if valid:mask |= 4
    if kind!=3:
        code |= parity(auth)<<3
        if valid:mask |= 8
    if kind in (1,3):
        for lane in range(8):code |= parity(bitrange(data,64*lane,64))<<(4+lane)
        if valid:mask |= 0xff0
    if kind==3:
        code |= parity(be)<<12
        if valid:mask |= 0x1000
    return code,mask,auth

def cases(path,kind,ports):
    rng=random.Random(0x525800+kind*11+ports)
    records=[]
    width=WIDTHS[kind]
    def add(payload,flip=0,valid=1,drop=0,enabled=0):
        index=len(records);port=index%ports;vc=(index//ports)%4;pool=(index//5)%2
        code,mask,auth=protect(kind,payload,port,vc,pool,valid)
        errors=flip&mask
        ctl=int(bool(errors&7));data=int(bool(errors&0x1ff0));ae=int(bool(errors&8));profile=int(valid and not enabled and bool(auth))
        normalized=payload
        if data and kind in (1,3):normalized |= 1<<(2 if kind==1 else 0)
        nc,_,_=protect(kind,normalized,port,vc,pool,1)
        accepted=int(valid and not(ctl or ae or profile or drop))
        records.append((enabled,valid,drop,port,vc,pool,payload,code^flip,errors,ctl,data,ae,profile,normalized,nc,accepted))
    def noauth(value):
        if kind!=3:
            low=(118,555,37)[kind]
            value &= ~(((1<<64)-1)<<low)
        return value
    add(0)
    for bit in range(width):
        add(1<<bit)
        add(1<<bit,enabled=1)
    add(noauth((1<<width)-1))
    for bit in range(13):
        add(noauth(rng.getrandbits(width)),1<<bit)
        add(noauth(rng.getrandbits(width)),1<<bit,valid=0)
    for _ in range(96):add(noauth(rng.getrandbits(width)),rng.randrange(8192) if rng.randrange(4)==0 else 0)
    # Existing poison, zero BE, masked lanes, every physical data parity group.
    if kind in (1,3):
        for lane in range(8):
            poison=1<<(2 if kind==1 else 0)
            add(poison,1<<(4+lane));add(0,1<<(4+lane))
    for _ in range(8):add(noauth(rng.getrandbits(width)),drop=1)
    path.write_text(''.join(' '.join(f'{v:x}' for v in row)+'\n' for row in records))
    return {'rows':len(records),'accepted':sum(r[-1] for r in records),'kind':kind,'ports':ports,'full_width':width}

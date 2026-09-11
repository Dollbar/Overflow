"""Control fields to ordered Data/ByteEnable half-flits, confirmed Common2.0 paths.
This derives tenure, not complete command/address/credit/payload legality.
"""
class UnresolvedTenure(ValueError):
    pass

def derive_control(word):
    if type(word) is not int or not 0<=word<(1<<256):raise ValueError('unsigned 256-bit Control required')
    end=8
    records=[]
    while end:
        kind=(word>>(32*end-4))&15
        if kind in (6,7):raise UnresolvedTenure('Table5-27 conflicts with Tables5-35/38')
        if kind>5:raise ValueError('reserved field type')
        width=(1,4,2,2,1,1)[kind]
        start=end-width
        if start<0 or start%width:raise ValueError('unaligned field')
        value=(word>>(32*start))&((1<<(32*width))-1)
        tokens=''
        if kind==1:
            cmd=(value>>118)&63
            count=value&3
            if cmd in (0x20,0x21,0x22,0x2a):raise UnresolvedTenure('special command byte-enable tenure requires dedicated section review')
            if cmd in (3,4,5) or 8<=cmd<=15:tokens=''
            elif cmd in (0x30,0x32,0x33):
                if count!=0:raise ValueError('standard atomic requires one UPLI beat')
                tokens='DDB'
            elif cmd in (0x23,0x26,0x27,0x28,0x29) or 0x2c<=cmd<=0x2f or 0x3c<=cmd<=0x3f:
                tokens='D'*(2*(count+1))
                if cmd not in (0x23,0x27,0x29):tokens+='B'
            else:raise ValueError('reserved request command')
        elif kind==2:
            if (value>>37)&1:tokens='D'*(2*(((value>>44)&3)+1))
        elif kind==3:
            cmd=(value>>57)&7
            if cmd>=3:
                tokens='D'*(2*(((value>>39)&3)+1))
                if cmd in (3,4):tokens+='B'
        elif kind==4:tokens='DD'
        elif kind==5:
            if (value>>1)&1:tokens='D'*(2*(((value>>2)&3)+1))
        if kind:records.append(dict(sector=start,kind=kind,tenure=tuple(tokens)))
        end=start
    records.sort(key=lambda item:item['sector'])
    return dict(fields=len(records),tenure=tuple(token for record in records for token in record['tenure']),records=records)

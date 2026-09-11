"""Immutable stimulus and original-byte expectations; never imports RTL/model codec.
Run via run.py. Outputs fixture hex in that run directory. Next inspect full tuple mismatches.
"""
from pathlib import Path

def vectors():
    out=[]
    for cmd in (3,0x28):
        for length in range(64):
            size=4*(length+1)
            start=4*((length*7)%((256-size)//4+1))
            out.append((cmd,length,start))
    for n in range(1,5):
        for start in range(0,257-64*n,64):out.append((0x29,16*n-1,start))
    return out

def write(root:Path):
    rows=[]
    for i,(cmd,length,start) in enumerate(vectors()):
        n=0 if cmd==3 else (start%64+4*(length+1)+63)//64
        fields=[(2,2),(64,0x8000000000000001 ^ (i<<17)),(10,777),(10,999),(11,1024+i),(2,0 if cmd==3 else n-1),(57,(1<<56)+0x2000+start),(6,cmd),(6,length),(8,(i*37)&255),(8,i^0xa5)]
        req=0
        for bits,value in fields:req=(req<<bits)|value
        beats=[];be=0;data=0;poison=0;pools=0
        for b in range(4):
            raw=bytes(((i*19+b*71+j*29) ^ (j>>2))&255 for j in range(64))
            mask=0 if i%11==0 else (0xf0ff55aacc338001 ^ (1<<b))
            err=(i>>b)&1;pool=(i+b)&1
            beats.append((int.from_bytes(raw,'little')<<68)|(mask<<4)|(b<<2)|((b==n-1)<<1)|err)
            if b<n:
                # Expected descriptor assembled independently by original byte addresses.
                for j,val in enumerate(raw):data|=val<<(b*512+j*8)
                for j in range(64):be|=((mask>>j)&1)<<(b*64+j)
                poison|=err<<b;pools|=pool<<b
        rows.append((req,n,beats,data,be,poison,pools))
    def dump(name,width,values):(root/name).write_text(''.join(f'{v:0{(width+3)//4}x}\n' for v in values))
    dump('request.hex',184,[r[0] for r in rows]);dump('n.hex',3,[r[1] for r in rows])
    dump('orig.hex',580,[b for r in rows for b in r[2]])
    dump('data.hex',2048,[r[3] for r in rows]);dump('be.hex',256,[r[4] for r in rows])
    dump('poison.hex',4,[r[5] for r in rows]);dump('pools.hex',4,[r[6] for r in rows])
    return len(rows)

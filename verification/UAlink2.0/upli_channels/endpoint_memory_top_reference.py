"""Independent byte-array memory and fixed native-response fixtures; never reads RTL state."""
from pathlib import Path

def vectors(path:Path,ports:int):
 memory=[bytearray((p*13+i*3+7)&255 for i in range(256)) for p in range(ports)]
 prefixes=[24,24,0,2,1,2,1,2]
 rows=[]
 for epoch,prefix in enumerate(prefixes):
  trial=[bytearray(m) for m in memory]
  for k in range(24):
   port=k%ports;vc=(k//ports)%4;pool=k%2;write=k%3!=1;n=k%4+1 if write else 4
   if write:
    for beat in range(n):
     seed=k*4+beat+1+epoch*1000
     values=bytes((seed*17+lane*29)&255 for lane in range(64))
     mask=0xf0ff55aacc338001^(1<<beat)
     if k%2:trial[port][beat*64:beat*64+64]=values
     else:
      for lane,value in enumerate(values):
       if (mask>>lane)&1:trial[port][beat*64+lane]=value
   data=int.from_bytes(trial[port],'little');status=0 if write else (0,2,3,6,8)[k%5];poison=9
   rd=[]
   for beat in range(4):
    value=int.from_bytes(trial[port][beat*64:beat*64+64],'little')
    # Frozen existing native payload bits; Auth disabled test value zero.
    word=(999<<545)|(777<<535)|((1024+k)<<524)|((n-1)<<522)|(value<<10)|(status<<6)|(beat<<4)|((beat==n-1)<<3)|(((poison>>beat)&1)<<2)
    rd.append(word)
   wr=((1024+k)<<24)|(status<<20)|(999<<10)|777
   rows.append(' '.join(f'{v:x}' for v in [data,status,poison,*rd,wr]))
   if k+1==prefix:memory=[bytearray(m) for m in trial]
 path.write_text('\n'.join(rows)+'\n')
 return {'epochs':8,'rows':len(rows),'executed_prefixes':prefixes,'scope':'independent byte writes and native payload bit constants; memory persists common transport reset'}

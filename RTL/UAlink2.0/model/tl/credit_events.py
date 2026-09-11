"""Common2.0 5.8/5.9.6 wire credit grants and 5.9 message events.
Each class has bins [pool,VC0,VC1,VC2,VC3]; no credit balance or transmit policy.
"""
def decode(lower,upper,msg,control):
 empty=dict(valid=False,grants=(0,)*20,nop=0,init=0,shared=0,poison=0)
 types=[lower&255,upper&255]
 if any((msg>>i)&1 and types[i] not in (0,1,32) for i in range(2)):return empty
 if control and msg&1:return empty
 fields=[]
 if control:
  # Low-to-high prefix grammar, independent of the RTL alignment tree.
  prefix=[[]]+[None]*8
  for end in range(1,9):
   kind=(lower>>(32*end-4))&15
   width={0:1,1:4,2:2,3:2,4:1,5:1}.get(kind,9);start=end-width
   if start>=0 and start%width==0 and prefix[start] is not None:prefix[end]=prefix[start]+[(start,kind)]
  if prefix[8] is None:return empty
  fields=prefix[8]
 grants=[0]*20
 for start,kind in fields:
  if kind:continue
  word=(lower>>(32*start))&0xffffffff
  for cls,(width,offset) in enumerate(((6,22),(6,16),(8,8),(8,0))):
   value=(word>>offset)&((1<<width)-1);is_vc=value>>(width-1);vc=(value>>(width-3))&3;amount=value&((1<<(width-3))-1)
   grants[cls*5+(vc+1 if is_vc else 0)]+=amount
 nop=init=shared=poison=0
 for i,word in enumerate((lower,upper)):
  if not (msg>>i)&1:continue
  if types[i]==0:nop|=1<<i
  elif types[i]==32:poison|=1<<i
  else:init|=1<<i;shared|=((word>>8)&1)<<i
 return dict(valid=True,grants=tuple(grants),nop=nop,init=init,shared=shared,poison=poison)

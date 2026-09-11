"""Content monitor for preclassified complete Flits; not a complete TL receiver.
Classes: Control0 Data1 BE2 MandatoryNOP3 Message4 Poison5 Auth6 Quiet7.
Pair order follows consumed Data/operand halves, ignoring inserted Messages.
"""
class Content:
 def __init__(self):self.open=False;self.poison=False;self.fatal=False
 def step(self,classes,words,tags,transfer=True,reset=False):
  if reset:
   self.__init__();return dict(allowed=False,taken=False,rejected=False)
  opened,poison=self.open,self.poison;bad=False
  for kind,word in zip(classes,words):
   if kind==3 and word:bad=True
   if kind==6 and (not 1<=tags<=4 or word>>(64*tags)):bad=True
   if kind in (1,5):
    mark=kind==5
    if opened:
     if poison!=mark:bad=True
     opened,poison=False,False
    else:opened,poison=True,mark
   elif kind==2 and opened:bad=True
  allowed=not self.fatal and not bad;taken=bool(transfer and allowed)
  if transfer:
   if bad:self.fatal=True
   elif taken:self.open,self.poison=opened,poison
  return dict(allowed=allowed,taken=taken,rejected=bool(transfer and not allowed))

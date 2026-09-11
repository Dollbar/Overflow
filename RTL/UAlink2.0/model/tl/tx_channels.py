"""Independent prepared Request/Response source selection before the real TL packer.
Lane 0 is Request, lane 1 Response. External sources own and hold their queued words.
"""
from tx_packer import Packer
from tl_tenure import derive_control
from credit_admission import admit
class Channels:
    def __init__(self):
        self.preferred=0
        self.held=None
        self.owner=0
        self.packer=Packer()
    def step(self, *, sources,pending,auth,done,shared,available,capacity,request_budget,
             response_budget,fc_valid,fc,fc_msg,transfer=True,reset=False):
        if reset:self.__init__()
        ready=[];nop=[];valid=[];error=0;shortfall=0
        for lane,s in enumerate(sources):
            try:d=derive_control(s['header'])
            except ValueError:d=None
            allowed_kinds=(1,3) if lane==0 else (2,4,5)
            fmt=bool(d and d['fields'] and all(x['kind'] in allowed_kinds for x in d['records']) and (not auth or d['fields']<=4))
            if s['valid'] and not fmt:error|=1<<lane
            allow,_,short=admit(s['header'],available,capacity,shared=shared,done=done) if fmt else (False,False,False)
            if s['valid'] and short:shortfall|=1<<lane
            budget=bool(fmt and d['fields']<=(request_budget if lane==0 else response_budget))
            payload=(sources[self.owner]['data_valid']>=1 if pending else s['tags_valid'] if auth else not d['tenure'] or s['data_valid']>=1) if fmt else False
            valid.append(s['valid'] and fmt)
            ready.append(valid[-1] and allow and budget and payload and pending<=1 and not(auth and pending==1) and not(pending==1 and fc_valid and fc_msg!=0))
            nop.append(valid[-1] and allow and not budget)
        selected=self.held
        if selected is None:
            for level in (ready,nop,valid):
                selected=next((j for j in (self.preferred,1-self.preferred) if level[j]),None)
                if selected is not None:break
        if selected is None:selected=self.preferred
        lane=self.owner if pending else selected;s=sources[selected];data=sources[lane]
        out=self.packer.step(pending=pending,auth=auth,done=done,shared=shared,available=available,capacity=capacity,request_budget=request_budget,response_budget=response_budget,header_valid=valid[selected],header=s['header'],tags_valid=s['tags_valid'],tags=s['tags'],data_valid=data['data_valid'],data0=data['data0'],data1=data['data1'],fc_valid=fc_valid,fc=fc,fc_msg=fc_msg,transfer=transfer,reset=reset)
        ht=(1<<selected) if out['header_taken'] else 0;tt=(1<<selected) if out['tags_taken'] else 0;dt=[0,0];dt[lane]=out['data_taken']
        if ht:self.owner=selected;self.preferred=1-selected
        self.held=selected if out['valid'] and not transfer else None
        out.update(header_taken=ht,tags_taken=tt,data_taken=tuple(dt),header_error=0 if reset else error,capacity_shortfall=0 if reset else shortfall)
        return out

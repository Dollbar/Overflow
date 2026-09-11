"""Prepared-Control/Data/FC packing, Common 2.0 confirmed tenure profile.
Sources keep queue entries stable until the actual wire-taken acknowledgement.
This is not the upstream Request/Response queue arbiter or an oversized splitter.
"""
from credit_admission import admit
from tl_tenure import derive_control

class Packer:
    def __init__(self):
        self.prefer_fc=True
        self.held=None

    def step(self, *, pending,auth,done,shared,available,capacity,request_budget,
             response_budget,header_valid,header,tags_valid,tags,data_valid,
             data0,data1,fc_valid,fc,fc_msg,transfer=True,reset=False):
        if reset:
            self.__init__()
            return dict(valid=False,flit=0,msg=0,header_taken=False,tags_taken=False,data_taken=0,fc_taken=False)
        try:decoded=derive_control(header)
        except ValueError:decoded=None
        allowed=bool(decoded and decoded['fields'] and (not auth or decoded['fields']<=4))
        credit=allowed and admit(header,available,capacity,shared=shared,done=done)[0]
        req=sum(r['kind'] in (1,3) for r in decoded['records']) if decoded else 0
        rsp=decoded['fields']-req if decoded else 0
        budget=req<=request_budget and rsp<=response_budget
        needs_data=bool(decoded and decoded['tenure'])
        payload=(data_valid>=1 if pending==1 else tags_valid if auth else data_valid>=1 if needs_data else True)
        hr=header_valid and credit and budget and payload and pending<=1 and not (auth and pending==1) and not (pending==1 and fc_valid and fc_msg!=0)
        fr=fc_valid and (pending==0 or (pending==1 and data_valid>=1 and fc_msg==0))
        choice=None
        if self.held is not None:choice=self.held
        elif pending>1:
            if data_valid>=2:choice='data'
        elif fr and (not hr or self.prefer_fc):choice='fc'
        elif hr:choice='header'
        elif pending==1 and data_valid>=1:choice='tail'
        elif pending==0 and header_valid and credit and not budget:choice='nop'
        flit=0;msg=0;data=0;tag=False
        if choice=='data':flit=data0|(data1<<256);data=2
        elif choice=='tail':flit=data0<<256;data=1
        elif choice=='fc':
            flit=fc;msg=fc_msg
            if pending==1:flit=(fc&((1<<256)-1))|(data0<<256);data=1
        elif choice=='header':
            flit=header
            if pending==1:flit|=data0<<256;data=1
            elif auth:flit|=tags<<256;tag=True
            elif needs_data:flit|=data0<<256;data=1
        valid=choice is not None;take=valid and transfer
        if take:
            if choice=='fc':self.prefer_fc=False
            elif choice=='header':self.prefer_fc=True
        self.held=choice if valid and not transfer else None
        return dict(valid=valid,flit=flit,msg=msg,header_taken=take and choice=='header',tags_taken=take and tag,data_taken=data if take else 0,fc_taken=take and choice=='fc')

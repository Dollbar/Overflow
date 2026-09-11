"""Ordinary uncompressed Read semantics independent of RTL helpers (Common 2.0).

ReadResponse is one reconstructed UPLI-like Beat event, not a TL packet.
The collector keeps every Tag until all N Beats and application retirement.
Local policy: VC0/VC credits; successful application data masks inactive bytes
zero; any transaction error or poison suppresses all application data. Raw
memory responses preserve natural lanes, including inactive in-range bytes.
"""
from dataclasses import dataclass

READ_STATUSES=(0,2,3,6,8)


def _uint(value,width,name):
    if type(value) is not int:raise TypeError(name+' must be an integer')
    if not 0<=value<1<<width:raise ValueError(name+' exceeds unsigned width')


def _boolean(value,name):
    if type(value) is not bool:raise TypeError(name+' must be boolean')


@dataclass(frozen=True)
class ReadRequest:
    port:int
    tag:int
    address:int
    src:int
    dst:int
    length:int=15
    attr:int=255
    vc:int=0
    pool:bool=False
    asi:int=0
    metadata:int=0


def validate_read(request):
    if type(request) is not ReadRequest:raise TypeError('ReadRequest required')
    for name,width in (('port',2),('tag',11),('address',57),('src',10),('dst',10),('length',6),('attr',8),('vc',2),('asi',2),('metadata',8)):
        _uint(getattr(request,name),width,name)
    _boolean(request.pool,'pool')
    if request.address%4 or request.address%256+4*(request.length+1)>256:
        raise ValueError('Read must be DWORD aligned within one 256-byte region')
    if request.vc or request.pool:raise ValueError('local profile uses VC0 and VC credits')


@dataclass(frozen=True)
class ByteMasks:
    region:int
    relative:int
    beats:int


def byte_masks(request):
    """Region bit0 is ADDR&~255; relative bit0 is ADDR&~63, never ADDR itself."""
    validate_read(request)
    first=request.attr & 15
    region=first << (request.address%256)
    if request.length:
        region|=(request.attr>>4) << (request.address%256+4*request.length)
        if request.length>1:
            region|=((1<<(4*(request.length-1)))-1) << (request.address%256+4)
    begin=request.address//64
    end=(request.address+4*(request.length+1)-1)//64
    return ByteMasks(region,region>>(request.address%256//64*64),end-begin+1)


def encode_read(request):
    """Natural 128-bit ordinary request field, CMD03 and NUMBEATS0."""
    validate_read(request)
    return ((1<<124)|(3<<118)|(request.vc<<116)|(request.asi<<114)|(request.tag<<103)
            |(int(request.pool)<<102)|(request.attr<<94)|(request.length<<88)|(request.metadata<<80)
            |((request.address>>2)<<25)|(request.src<<15)|(request.dst<<5))


def decode_read(word,*,port):
    _uint(word,128,'request field')
    if word>>124!=1 or (word>>118)&63!=3 or word&19:
        raise ValueError('ordinary Read CMD03, no cache load, NUMBEATS0 required')
    request=ReadRequest(port=port,tag=(word>>103)&2047,address=((word>>25)&((1<<55)-1))<<2,
                        src=(word>>15)&1023,dst=(word>>5)&1023,length=(word>>88)&63,
                        attr=(word>>94)&255,vc=(word>>116)&3,pool=bool((word>>102)&1),
                        asi=(word>>114)&3,metadata=(word>>80)&255)
    validate_read(request)
    return request


@dataclass(frozen=True)
class ReadResponse:
    port:int
    tag:int
    src:int
    dst:int
    data:int
    status:int=0
    offset:int=0
    last:bool=True
    num_beats:int=0
    rsp_type:int=0
    vc:int=0
    pool:bool=False
    data_error:bool=False


def validate_response(response):
    if type(response) is not ReadResponse:raise TypeError('ReadResponse required')
    for name,width in (('port',2),('tag',11),('src',10),('dst',10),('data',512),('status',4),('offset',2),('num_beats',2),('rsp_type',2),('vc',2)):
        _uint(getattr(response,name),width,name)
    for name in ('last','pool','data_error'):_boolean(getattr(response,name),name)
    if response.status not in READ_STATUSES:raise ValueError('unsupported ordinary Read status')
    if response.rsp_type or response.vc or response.pool:raise ValueError('ordinary unicast VC0/VC-credit response required')


def encode_response(response):
    """Encode one Single-Beat Header; multi events use the burst decoder only.

    OFFSET/LAST are per-event UPLI fields for multi mode and cannot each become
    separate TL Headers. This sender deliberately selects Single-Beat mode.
    """
    validate_response(response)
    if response.num_beats:raise ValueError('encoder selects Single-Beat response mode')
    return ((2<<60)|(response.tag<<47)|(response.offset<<42)|(response.status<<38)
            |(1<<37)|(int(response.last)<<36)|(response.src<<26)|(response.dst<<16))


def decode_response_burst(word,*,port,data_beats,poison=None):
    """Decode complete TL tenure into natural Beat events.

    Single LEN0 preserves OFFSET/LAST. Multi LEN>0 reconstructs OFFSET0..N-1
    and final LAST from complete Data tenure, ignoring inactive OFFSET and the
    unresolved raw Header LAST reduction. No missing or extra payload allowed.
    SPARE is ignored. Poison is supplied by the Data path, never status-derived.
    """
    _uint(word,64,'response field');_uint(port,2,'port')
    if word>>60!=2 or not word&(1<<37):raise ValueError('ordinary Read response required')
    count=((word>>44)&3)+1
    if type(data_beats) is not tuple or len(data_beats)!=count:raise ValueError('complete declared Data tenure required')
    if poison is None:poison=(False,)*count
    if type(poison) is not tuple or len(poison)!=count:raise ValueError('one poison flag per Beat required')
    events=[]
    for index,data in enumerate(data_beats):
        event=ReadResponse(port=port,tag=(word>>47)&2047,src=(word>>26)&1023,dst=(word>>16)&1023,
                           data=data,status=(word>>38)&15,offset=index if count>1 else (word>>42)&3,
                           last=index==count-1 if count>1 else bool((word>>36)&1),num_beats=count-1,
                           rsp_type=(word>>14)&3,vc=(word>>58)&3,pool=bool((word>>46)&1),data_error=poison[index])
        validate_response(event);events.append(event)
    return tuple(events)


@dataclass(frozen=True)
class ByteMemory:
    data:bytes
    base_address:int=0
    executions:int=0

    def __post_init__(self):
        if type(self.data) is not bytes:raise TypeError('immutable bytes required')
        _uint(self.base_address,57,'memory base')
        if type(self.executions) is not int or self.executions<0:raise ValueError('nonnegative execution count required')
        if self.base_address+len(self.data)>1<<57:raise ValueError('memory exceeds address width')


@dataclass(frozen=True)
class MemoryResult:
    memory:ByteMemory
    responses:tuple[ReadResponse,...]
    masks:ByteMasks


def memory_read(request,memory,*,status=0,error_pattern=0):
    """One actual backend result event, including zero-BE/error attempts.

    The declared DWORD interval must be mapped; this local decode policy does
    not change with disabled BE. Natural Beat bytes outside that interval are
    preserved where mapped and zero-filled where outside the memory window.
    Explicit nonzero status takes priority over local address decode.
    """
    validate_read(request)
    if type(memory) is not ByteMemory:raise TypeError('ByteMemory required')
    _uint(status,4,'status');_uint(error_pattern,8,'error_pattern')
    if status not in READ_STATUSES:raise ValueError('unsupported backend status')
    start=request.address-memory.base_address
    if status==0 and (start<0 or start+4*(request.length+1)>len(memory.data)):status=3
    masks=byte_masks(request);base=request.address//64*64;responses=[]
    for offset in range(masks.beats):
        raw=bytearray(64)
        for lane in range(64):
            address=base+offset*64+lane
            if status:byte=error_pattern
            elif memory.base_address<=address<memory.base_address+len(memory.data):
                byte=memory.data[address-memory.base_address]
            else:byte=0
            raw[lane]=byte
        responses.append(ReadResponse(port=request.port,tag=request.tag,src=request.dst,dst=request.src,data=int.from_bytes(raw,'little'),
                                      status=status,offset=offset,last=offset==masks.beats-1))
    return MemoryResult(ByteMemory(memory.data,memory.base_address,memory.executions+1),tuple(responses),masks)


@dataclass(frozen=True)
class Completion:
    port:int
    tag:int
    status:int
    data:int
    requested_mask:int
    valid_mask:int
    num_beats:int
    poison_mask:int


class ReadCollector:
    """Own (port,tag) until all responses arrive and the application retires.

    Single-Beats may reorder/interleave across Tags. A Multi-Beat burst stays
    contiguous per port and its event OFFSET/LAST sequence is exact. Validation
    is atomic: rejected events leave all ownership and previously saved data
    unchanged. Response SRC is debug-only and is never identity matching.
    Reset drops all ownership; same-Tag stale responses after legal reuse are
    not distinguishable without an additional external epoch protocol.
    """
    def __init__(self,*,local_id,capacity=4,num_ports=1):
        _uint(local_id,10,'local_id')
        if type(capacity) is not int or capacity<1:raise ValueError('positive capacity required')
        if type(num_ports) is not int or not 1<=num_ports<=4:raise ValueError('one through four ports required')
        self.local_id=local_id;self.capacity=capacity;self.num_ports=num_ports;self._slots={};self._multi_owner={}

    @property
    def occupancy(self):return len(self._slots)

    def _key(self,port,tag):
        _uint(port,2,'port');_uint(tag,11,'tag')
        if port>=self.num_ports:raise ValueError('port is not configured')
        return port,tag

    def reserve(self,request):
        validate_read(request);key=self._key(request.port,request.tag)
        if request.src!=self.local_id or key in self._slots or self.occupancy>=self.capacity:raise ValueError('wrong origin, duplicate Tag or full capacity')
        self._slots[key]=dict(request=request,sent=False,seen={},status=None,mode=None,completion=None)

    def mark_sent(self,port,tag):
        key=self._key(port,tag)
        if key not in self._slots or self._slots[key]['sent']:raise ValueError('unknown or already sent Tag')
        self._slots[key]={**self._slots[key],'sent':True}

    def receive(self,response):
        validate_response(response);key=self._key(response.port,response.tag)
        if key not in self._slots:raise ValueError('unknown response Tag')
        state=self._slots[key];mask=byte_masks(state['request'])
        if not state['sent'] or state['completion'] is not None or response.dst!=self.local_id:raise ValueError('unexpected response phase or destination')
        if self._multi_owner.get(response.port,key)!=key:raise ValueError('interleaving a Multi-Beat burst on the same port')
        if response.offset>=mask.beats:raise ValueError('response offset outside request')
        if response.offset in state['seen']:
            raise ValueError('duplicate response offset')
        mode='single' if response.num_beats==0 else 'multi'
        if state['mode'] is not None and state['mode']!=mode:raise ValueError('response mode changed within transaction')
        if state['status'] is not None and state['status']!=response.status:raise ValueError('response status changed within transaction')
        if mode=='multi' and (response.num_beats!=mask.beats-1 or response.offset!=len(state['seen'])):raise ValueError('Multi-Beat length or sequence mismatch')
        seen={**state['seen'],response.offset:response}
        done=len(seen)==mask.beats
        if response.last!=done:raise ValueError('LAST must accompany the final arriving Beat')
        completion=None
        if done:
            poison_mask=sum(1<<offset for offset,event in seen.items() if event.data_error)
            valid_mask=mask.relative if response.status==0 and poison_mask==0 else 0
            raw=sum(event.data<<(512*offset) for offset,event in seen.items())
            # Byte expansion here is separate from the nibble arithmetic in byte_masks.
            data=sum(((raw>>(8*byte))&255)<<(8*byte) for byte in range(64*mask.beats) if valid_mask&(1<<byte))
            completion=Completion(response.port,response.tag,response.status,data,mask.relative,valid_mask,mask.beats,poison_mask)
        self._slots[key]={**state,'seen':seen,'mode':mode,'status':response.status,'completion':completion}
        if mode=='multi':
            if done:self._multi_owner.pop(response.port,None)
            else:self._multi_owner[response.port]=key
        return completion

    def peek(self,port,tag):
        key=self._key(port,tag)
        if key not in self._slots:raise ValueError('unknown Tag')
        return self._slots[key]['completion']

    def retire(self,port,tag):
        completion=self.peek(port,tag)
        if completion is None:raise ValueError('all response Beats not yet received')
        del self._slots[(port,tag)]
        return completion

    def reset(self):
        self._slots.clear();self._multi_owner.clear()

"""Independent ordinary uncompressed Write/WriteFull semantics (Common 2.0).

Tables 5-29/30 specify wire fields; section 2.8 specifies byte lanes and masks.
This local profile has VC0, no pool/auth/compression/poison, and opaque ASI/ATTR/META.
Backend and Tag methods are semantic events, not cycle-accurate UPLI handshakes.
"""
from dataclasses import dataclass

WRITE_STATUSES = (0, 2, 3, 6, 8)


def _uint(value, width, name):
    if type(value) is not int:
        raise TypeError(name + ' must be an integer')
    if not 0 <= value < 1 << width:
        raise ValueError(name + ' exceeds unsigned width')


def _bool(value, name):
    if type(value) is not bool:
        raise TypeError(name + ' must be boolean')


@dataclass(frozen=True)
class WriteRequest:
    port: int
    tag: int
    address: int
    src: int
    dst: int
    data_beats: tuple[int, ...]
    byte_enable: int
    full: bool = False
    length: int = 15
    attr: int = 0
    vc: int = 0
    pool: bool = False
    asi: int = 0
    metadata: int = 0


@dataclass(frozen=True)
class WriteResponse:
    port: int
    tag: int
    src: int
    dst: int
    status: int = 0
    offset: int = 0
    last: bool = False
    num_beats: int = 0
    rsp_type: int = 0
    vc: int = 0
    pool: bool = False
    data_error: bool = False


def _beat_count(request):
    return ((request.address & 63) + 4*(request.length+1) + 63)//64


def _range_mask(request):
    return ((1 << (4*(request.length+1))) - 1) << (request.address & 255)


def validate_write(request):
    if type(request) is not WriteRequest:
        raise TypeError('WriteRequest required')
    for name,width in (('port',2),('tag',11),('address',57),('src',10),('dst',10),
                       ('length',6),('attr',8),('vc',2),('asi',2),('metadata',8),('byte_enable',256)):
        _uint(getattr(request,name),width,name)
    _bool(request.full,'full'); _bool(request.pool,'pool')
    size=4*(request.length+1)
    if request.address & 3 or (request.address & 255)+size > 256:
        raise ValueError('unaligned or crossing a 256-byte region')
    if request.full and (request.address & 63 or size % 64):
        raise ValueError('WriteFull requires whole naturally aligned 64-byte beats')
    if not request.full and request.byte_enable & ~_range_mask(request):
        raise ValueError('byte enable outside requested address range')
    if request.vc or request.pool:
        raise ValueError('local profile requires VC0 and VC credits')
    if type(request.data_beats) is not tuple or len(request.data_beats)!=_beat_count(request):
        raise ValueError('complete ordered tuple of exactly N data beats required')
    for beat in request.data_beats:
        _uint(beat,512,'data beat')


def effective_byte_enable(request):
    """256-byte-region mask; application WriteFull input BE is ignored."""
    validate_write(request)
    return _range_mask(request) if request.full else request.byte_enable


def data_halves(request):
    """Relative Beat0 low/high through BeatN; ordinary Write appends region BE."""
    validate_write(request)
    halves=tuple(half for beat in request.data_beats for half in (beat & ((1<<256)-1),beat>>256))
    return halves if request.full else halves+(request.byte_enable,)


def encode_write(request):
    """One natural 128-bit request field; CLOAD/CWAY zero, no Control padding."""
    validate_write(request)
    return ((1<<124)|((0x29 if request.full else 0x28)<<118)|(request.vc<<116)
            |(request.asi<<114)|(request.tag<<103)|(int(request.pool)<<102)
            |(request.attr<<94)|(request.length<<88)|(request.metadata<<80)
            |((request.address>>2)<<25)|(request.src<<15)|(request.dst<<5)
            |(_beat_count(request)-1))


def decode_write(word, *, port, data_beats, byte_enable):
    """Decode complete transaction; CLOAD unsupported, inactive CWAY ignored."""
    _uint(word,128,'request field')
    command=(word>>118)&63
    if word>>124!=1 or command not in (0x28,0x29) or word&(1<<4):
        raise ValueError('unsupported request type, command or cache load')
    request=WriteRequest(port=port,tag=(word>>103)&2047,address=((word>>25)&((1<<55)-1))<<2,
                         src=(word>>15)&1023,dst=(word>>5)&1023,data_beats=data_beats,byte_enable=byte_enable,
                         full=command==0x29,length=(word>>88)&63,attr=(word>>94)&255,
                         vc=(word>>116)&3,pool=bool((word>>102)&1),asi=(word>>114)&3,metadata=(word>>80)&255)
    validate_write(request)
    if (word&3)!=_beat_count(request)-1:
        raise ValueError('NUMBEATS disagrees with address and length')
    return request


def validate_response(response):
    if type(response) is not WriteResponse:
        raise TypeError('WriteResponse required')
    for name,width in (('port',2),('tag',11),('src',10),('dst',10),('status',4),
                       ('offset',2),('num_beats',2),('rsp_type',2),('vc',2)):
        _uint(getattr(response,name),width,name)
    for name in ('last','pool','data_error'):
        _bool(getattr(response,name),name)
    if response.status not in WRITE_STATUSES:
        raise ValueError('unsupported ordinary Write status')
    if response.num_beats or response.rsp_type or response.vc or response.pool or response.data_error:
        raise ValueError('local ordinary Write response has no data, VC0 and no pool')
    # OFFSET/LAST are invalid for Write, so any value within their width is accepted.


def encode_response(response):
    """One 64-bit response field, with ignored OFFSET/LAST and SPARE emitted zero."""
    validate_response(response)
    return ((2<<60)|(response.vc<<58)|(response.tag<<47)|(int(response.pool)<<46)
            |(response.status<<38)|(response.src<<26)|(response.dst<<16))


def decode_response(word, *, port):
    _uint(word,64,'response field')
    if word>>60!=2 or word&(1<<37):
        raise ValueError('ordinary uncompressed Write response required')
    response=WriteResponse(port=port,tag=(word>>47)&2047,src=(word>>26)&1023,dst=(word>>16)&1023,
                           status=(word>>38)&15,offset=(word>>42)&3,last=bool((word>>36)&1),
                           num_beats=(word>>44)&3,rsp_type=(word>>14)&3,vc=(word>>58)&3,pool=bool((word>>46)&1))
    validate_response(response)
    return response


@dataclass(frozen=True)
class ByteMemory:
    data: bytes
    base_address: int = 0
    executions: int = 0

    def __post_init__(self):
        if type(self.data) is not bytes:
            raise TypeError('immutable bytes required')
        _uint(self.base_address,57,'memory base')
        if type(self.executions) is not int or self.executions<0:
            raise ValueError('nonnegative execution count required')
        if self.base_address+len(self.data)>1<<57:
            raise ValueError('memory extends beyond address width')


@dataclass(frozen=True)
class MemoryResult:
    memory: ByteMemory
    response: WriteResponse


def memory_write(request, memory, *, status=0):
    """One backend result event, returning new bytes; failed attempts never update.

    Whole-operation no-update on errors is a local backend policy, not a claim
    of specified memory rollback/coherence. ASI/ATTR/META are opaque metadata.
    """
    validate_write(request)
    if type(memory) is not ByteMemory:
        raise TypeError('ByteMemory required')
    _uint(status,4,'status')
    if status not in WRITE_STATUSES:
        raise ValueError('unsupported backend status')
    start=request.address-memory.base_address
    if status==0 and (start<0 or start+4*(request.length+1)>len(memory.data)):
        status=3
    result=bytearray(memory.data)
    if status==0:
        mask=effective_byte_enable(request)
        beat_base=request.address&~63
        region_base=request.address&~255
        for j,beat in enumerate(request.data_beats):
            for lane in range(64):
                address=beat_base+64*j+lane
                if mask&(1<<(address-region_base)):
                    result[address-memory.base_address]=(beat>>(8*lane))&255
    response=WriteResponse(port=request.port,tag=request.tag,src=request.dst,dst=request.src,status=status,vc=request.vc,pool=False)
    return MemoryResult(ByteMemory(bytes(result),memory.base_address,memory.executions+1),response)


class WriteBackend:
    """accept owns a token; finish executes once; retire_response frees capacity.

    Finish may arrive in arbitrary token order. This model does not schedule
    coherent Read/Write dependencies or model the UPLI next-cycle timing rule.
    """
    def __init__(self, memory, *, local_id, capacity=4):
        if type(memory) is not ByteMemory: raise TypeError('ByteMemory required')
        _uint(local_id,10,'local_id')
        if type(capacity) is not int or capacity<1: raise ValueError('positive capacity required')
        self.memory=memory;self.local_id=local_id;self.capacity=capacity;self._slots={}

    def accept(self, token, request):
        _uint(token,64,'token');validate_write(request)
        if token in self._slots or len(self._slots)>=self.capacity or request.dst!=self.local_id:
            raise ValueError('duplicate token, no capacity or wrong destination')
        self._slots[token]=(request,None)

    def finish(self, token, *, status=0):
        _uint(token,64,'token')
        if token not in self._slots or self._slots[token][1] is not None:
            raise ValueError('unknown or already completed token')
        request,_=self._slots[token]
        result=memory_write(request,self.memory,status=status)
        self.memory=result.memory;self._slots[token]=(request,result.response)

    def peek_response(self, token):
        _uint(token,64,'token')
        if token not in self._slots: raise ValueError('unknown token')
        return self._slots[token][1]

    def retire_response(self, token):
        response=self.peek_response(token)
        if response is None: raise ValueError('backend result not received')
        del self._slots[token]
        return response


@dataclass(frozen=True)
class TagCompletion:
    port: int
    tag: int
    kind: str
    status: int


class ReadWriteTags:
    """Shared identity/event oracle only; Read payload assembly is out of scope.

    Keeps identity until application retirement. A stale response after legal
    reuse cannot be detected by Tag alone; reset epochs are not modelled here.
    """
    def __init__(self, *, local_id, capacity=4, num_ports=1):
        _uint(local_id,10,'local_id')
        if type(capacity) is not int or capacity<1 or type(num_ports) is not int or num_ports not in (1,2,4):
            raise ValueError('positive capacity and 1/2/4 ports required')
        self.local_id=local_id;self.capacity=capacity;self.num_ports=num_ports;self._slots={}

    @property
    def occupancy(self):
        return len(self._slots)

    def _key(self, port, tag):
        _uint(port,2,'port');_uint(tag,11,'tag')
        if port>=self.num_ports:raise ValueError('port not configured')
        return port,tag

    def reserve(self, port, tag, kind):
        key=self._key(port,tag)
        if kind not in ('read','write') or key in self._slots or self.occupancy>=self.capacity:
            raise ValueError('bad kind, duplicate identity or no capacity')
        self._slots[key]=(kind,False,None)

    def mark_sent(self, port, tag):
        key=self._key(port,tag)
        if key not in self._slots or self._slots[key][1]:raise ValueError('not reserved or already issued')
        kind,_,completion=self._slots[key]
        self._slots[key]=(kind,True,completion)

    def receive(self, port, tag, kind, status, dst):
        key=self._key(port,tag);_uint(status,4,'status');_uint(dst,10,'destination')
        if key not in self._slots:raise ValueError('unknown response identity')
        expected,sent,completion=self._slots[key]
        if kind!=expected or not sent or completion is not None or dst!=self.local_id:
            raise ValueError('wrong kind/destination or unexpected response phase')
        if status not in (WRITE_STATUSES if kind=='write' else (0,3)):
            raise ValueError('unsupported response status')
        self._slots[key]=(kind,sent,TagCompletion(port,tag,kind,status))

    def peek(self, port, tag):
        key=self._key(port,tag)
        if key not in self._slots:raise ValueError('unknown identity')
        return self._slots[key][2]

    def retire(self, port, tag):
        completion=self.peek(port,tag)
        if completion is None:raise ValueError('completion not received')
        del self._slots[(port,tag)]
        return completion

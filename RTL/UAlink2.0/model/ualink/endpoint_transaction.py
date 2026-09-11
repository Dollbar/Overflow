"""Common 2.0 ordinary uncompressed single-64-byte Read reference subset.

Wire field positions: Tables 5-29/30. Tag/routing: Tables 2-2/15 and 2.7.4.2.
Resource sizes, strict profile rejection and method calls are local model policy,
not UPLI handshakes, wire error responses or Link Down recovery behavior.
"""
from dataclasses import dataclass


def _unsigned(value, width, name):
    if type(value) is not int:
        raise TypeError(name + ' must be an integer')
    if not 0 <= value < 1 << width:
        raise ValueError(name + ' exceeds its unsigned width')


@dataclass(frozen=True)
class ReadRequest:
    port: int
    tag: int
    address: int
    src: int
    dst: int
    length: int = 15
    attr: int = 255
    vc: int = 0
    pool: bool = False
    asi: int = 0
    metadata: int = 0


@dataclass(frozen=True)
class ReadResponse:
    port: int
    tag: int
    src: int
    dst: int
    data_halves: tuple[int, int]
    status: int = 0
    offset: int = 0
    last: bool = True
    num_beats: int = 0
    rsp_type: int = 0
    vc: int = 0
    pool: bool = False
    data_error: bool = False


@dataclass(frozen=True)
class Completion:
    port: int
    tag: int
    status: int
    data: int | None


def validate_read(request):
    if type(request) is not ReadRequest:
        raise TypeError('ReadRequest required')
    for name, width in (('port',2), ('tag',11), ('address',57), ('src',10), ('dst',10), ('length',6), ('attr',8), ('vc',2), ('asi',2), ('metadata',8)):
        _unsigned(getattr(request, name), width, name)
    if type(request.pool) is not bool:
        raise TypeError('pool must be a boolean')
    if request.address & 63 or request.length != 15 or request.attr != 255:
        raise ValueError('local profile requires aligned full 64-byte Read')
    if request.vc or request.pool or request.asi or request.metadata:
        raise ValueError('local profile requires VC0/VC credit/ASI0/metadata0')


def validate_response(response):
    if type(response) is not ReadResponse:
        raise TypeError('ReadResponse required')
    for name, width in (('port',2), ('tag',11), ('src',10), ('dst',10), ('status',4), ('offset',2), ('num_beats',2), ('rsp_type',2), ('vc',2)):
        _unsigned(getattr(response, name), width, name)
    for name in ('last','pool','data_error'):
        if type(getattr(response, name)) is not bool:
            raise TypeError(name + ' must be a boolean')
    if response.status not in (0,3):
        raise ValueError('local profile supports OKAY and DECODE ERROR only')
    if response.offset or response.num_beats or not response.last or response.rsp_type:
        raise ValueError('local profile requires complete ordinary single-beat response')
    if response.vc or response.pool or response.data_error:
        raise ValueError('local profile requires VC0/VC credit and no DataError')
    if type(response.data_halves) is not tuple or len(response.data_halves) != 2:
        raise ValueError('exactly two complete Data half-flits required')
    for half in response.data_halves:
        _unsigned(half, 256, 'data half')


def encode_read(request):
    """Return one 128-bit Table5-29 field; no Control padding or DL framing."""
    validate_read(request)
    return ((1 << 124) | (3 << 118) | (request.vc << 116)
            | (request.asi << 114) | (request.tag << 103)
            | (int(request.pool) << 102) | (request.attr << 94)
            | (request.length << 88) | (request.metadata << 80)
            | ((request.address >> 2) << 25) | (request.src << 15)
            | (request.dst << 5))


def decode_read(word, *, port):
    """Decode a standalone field in the local subset; CLOAD/CWAY are inactive."""
    _unsigned(word, 128, 'request field')
    if word >> 124 != 1 or (word >> 118) & 63 != 3 or word & 31:
        raise ValueError('unsupported FTYPE/CMD/cache/NumBeats in local Read profile')
    request = ReadRequest(port=port, tag=(word >> 103) & 2047,
                          address=((word >> 25) & ((1 << 55)-1)) << 2,
                          src=(word >> 15) & 1023, dst=(word >> 5) & 1023,
                          length=(word >> 88) & 63, attr=(word >> 94) & 255,
                          vc=(word >> 116) & 3, pool=bool((word >> 102) & 1),
                          asi=(word >> 114) & 3, metadata=(word >> 80) & 255)
    validate_read(request)
    return request


def encode_response(response):
    """Return one 64-bit Table5-30 field from an already complete local beat."""
    validate_response(response)
    return ((2 << 60) | (response.vc << 58) | (response.tag << 47)
            | (int(response.pool) << 46) | (response.num_beats << 44)
            | (response.offset << 42) | (response.status << 38) | (1 << 37)
            | (int(response.last) << 36) | (response.src << 26)
            | (response.dst << 16) | (response.rsp_type << 14))


def decode_response(word, *, data_halves, port):
    """Complete beat decoder; a bare header is never a completion event.

    SPARE bits are not represented or used for identity. This helper does not
    prescribe a full protocol receiver's unassigned-bit error policy.
    """
    _unsigned(word, 64, 'response field')
    if word >> 60 != 2 or not (word & (1 << 37)):
        raise ValueError('ordinary uncompressed Read Response required')
    response = ReadResponse(port=port, tag=(word >> 47) & 2047,
                            src=(word >> 26) & 1023, dst=(word >> 16) & 1023,
                            data_halves=data_halves, status=(word >> 38) & 15,
                            offset=(word >> 42) & 3, last=bool((word >> 36) & 1),
                            num_beats=(word >> 44) & 3, rsp_type=(word >> 14) & 3,
                            vc=(word >> 58) & 3, pool=bool((word >> 46) & 1))
    validate_response(response)
    return response


def memory_read(request, memory):
    """Independent byte-array backend: full address bounds, natural little-endian lanes.

    The size of memory is explicit test configuration. This is neither a cache
    coherence model nor a synthesizable Completer or asynchronous service model.
    """
    validate_read(request)
    if type(memory) is not bytes:
        raise TypeError('immutable memory bytes required')
    if request.address + 64 > len(memory):
        status, halves = 3, (0,0)
    else:
        address = request.address
        status = 0
        halves = (int.from_bytes(memory[address:address+32], 'little'),
                  int.from_bytes(memory[address+32:address+64], 'little'))
    return ReadResponse(port=request.port, tag=request.tag, src=request.dst,
                        dst=request.src, data_halves=halves, status=status)


class ReadTracker:
    """Bounded local Tag/result reservations, with explicit sent and retired events.

    A completed result holds its slot until application retirement (conservative
    local policy). Methods are atomic semantic events, not a cycle/TDM model.
    Cross-port identity can be unit-tested with num_ports=2/4, while the initial
    RTL integration profile remains one port. Capacity is total across ports.
    """
    def __init__(self, *, local_id, capacity=4, num_ports=1):
        _unsigned(local_id,10,'local_id')
        if type(capacity) is not int or type(num_ports) is not int:
            raise TypeError('capacity and num_ports must be integers')
        if capacity < 1 or num_ports not in (1,2,4):
            raise ValueError('positive capacity and 1/2/4 ports required')
        self.local_id, self.capacity, self.num_ports = local_id, capacity, num_ports
        self._records = {}

    @property
    def occupancy(self):
        return len(self._records)

    def _key(self, port, tag):
        _unsigned(port,2,'port'); _unsigned(tag,11,'tag')
        if port >= self.num_ports:
            raise ValueError('port outside configured local identity domain')
        return port, tag

    def _record(self, port, tag):
        key = self._key(port, tag)
        if key not in self._records:
            raise ValueError('unknown or already retired Tag')
        return key, self._records[key]

    def reserve(self, request):
        validate_read(request)
        key = self._key(request.port, request.tag)
        if request.src != self.local_id:
            raise ValueError('request source differs from local identity')
        if key in self._records:
            raise ValueError('Tag still reserved until completed result retirement')
        if self.occupancy >= self.capacity:
            raise ValueError('no reserved request/result capacity')
        self._records[key] = (request, False, None)

    def mark_sent(self, port, tag):
        key, (request, sent, completion) = self._record(port, tag)
        if sent:
            raise ValueError('request already marked sent')
        self._records[key] = (request, True, completion)

    def receive(self, response):
        validate_response(response)
        key, (request, sent, completion) = self._record(response.port, response.tag)
        if not sent or completion is not None:
            raise ValueError('response before actual send or duplicate response')
        if response.dst != self.local_id:
            raise ValueError('response destination is not this Originator')
        # Response SRC is explicitly debug-only; it is never a matching key.
        data = response.data_halves[0] | (response.data_halves[1] << 256)
        result = Completion(response.port, response.tag, response.status,
                            data if response.status == 0 else None)
        self._records[key] = (request, sent, result)

    def peek(self, port, tag):
        return self._record(port, tag)[1][2]

    def retire(self, port, tag):
        key, (_, _, completion) = self._record(port, tag)
        if completion is None:
            raise ValueError('no complete response data to retire')
        del self._records[key]
        return completion

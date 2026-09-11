"""Stream0 UART reset requester/responder event reference for DL/PL2.0.

Normative sources: sections2.4.2.5 and2.4.4.1.2, Tables2-12/2-13.
service() commits one actually transmitted maintenance DWORD; an offer or stall
is not a transmission. advance_ps() supplies elapsed physical time explicitly.
This reference controls disable/block ownership, not payload storage, ordinary
DL arbitration, CRC/replay, credit advertisement cadence or a PHY clock.

Concurrent local and peer requests have independent ownership. During a local
run-out, peer responses wait behind all40 No-Ops and the local Request. Once
unblocked they are eligible for ordinary UART-message arbitration. Repeated
requests each retain one pending response in arrival order, including their
single/all scope. The reference queue is unbounded; a finite RTL queue must
establish its capacity/overflow contract before claiming equivalent behavior.
"""
from collections import deque
from dataclasses import dataclass


def _boolean(value,label):
    if type(value) is not bool:raise ValueError(label+' must be boolean')


def _three_bits(value,label):
    if type(value) is not int or not 0<=value<=7:raise ValueError(label+' must be an unsigned3-bit integer')


@dataclass(frozen=True)
class ResetMessage:
    """Immutable encoded maintenance DWORD; all transmitted reserved bits are zero."""

    kind: str
    word: int


class UARTResetSequencer:
    """Event-ordered reset ownership for the single currently defined UART stream.

    A wrapper must flush TX/RX and both credit directions whenever disabled,
    preserve RX message run-out, and preserve the independently managed Channel4
    state. On release it initializes RX credit to its actual buffer capacity.
    block_messages forbids ordinary DL words; the local reset sequence itself
    bypasses ordinary arbitration. A pending response outside this sequence is
    eligible for normal message arbitration and does not block other classes.

    A response can complete the local request only while waiting, with SUCCESS,
    and covering stream0. With only stream0, allStreams is scope, not a distinct
    transaction tag. Events execute in caller order; this is not a declaration
    of priorities for simultaneous signals at an RTL clock edge.
    """

    _TIMEOUT_PS=10_000_000_000

    def __init__(self):
        self.reset()

    def reset(self):
        """Global reset cancels local/peer work and holds the stream disabled."""
        self._held=True
        self._phase='normal'
        self._noops=0
        self._all_streams=False
        self._responses=deque()
        self._now_ps=0
        self._deadline_ps=None
        self._retries=0

    def release_reset(self):
        """Release global hold without inventing a firmware reset request."""
        self._held=False

    @property
    def stream_disabled(self):
        return self._held or self._phase!='normal' or bool(self._responses)

    @property
    def block_messages(self):
        return self._held or self._phase in ('noops','request')

    @property
    def waiting(self):
        return self._phase=='wait'

    @property
    def retries(self):
        return self._retries

    def request(self,*,all_streams=False):
        """Accept a firmware request once; busy/held returns False unchanged."""
        _boolean(all_streams,'all_streams')
        if self._held or self._phase!='normal':return False
        self._all_streams=all_streams
        self._start_runout()
        return True

    def _start_runout(self):
        self._phase='noops'
        self._noops=40
        self._deadline_ps=None

    def receive_request(self,*,stream_id=0,all_streams=False):
        """Consume a decoded boundary Request; disable before scheduling SUCCESS."""
        _three_bits(stream_id,'stream_id');_boolean(all_streams,'all_streams')
        if self._held or (stream_id!=0 and not all_streams):return False
        self._responses.append(all_streams)
        return True

    def receive_response(self,*,status,stream_id=0,all_streams=False):
        """Ignore reserved status and responses not covering a currently waiting stream."""
        _three_bits(status,'status');_three_bits(stream_id,'stream_id');_boolean(all_streams,'all_streams')
        if self._held or self._phase!='wait' or status!=0 or (stream_id!=0 and not all_streams):return False
        self._phase='normal'
        self._deadline_ps=None
        return True

    def offer(self):
        """Observe a maintenance word without transmitting or changing ownership."""
        if self._held:return None
        if self._phase=='noops':return ResetMessage('noop',0)
        if self._phase=='request':return ResetMessage('request',0x184|(int(self._all_streams)<<12))
        if self._responses:
            scope=self._responses[0]
            return ResetMessage('response',0x1C4|(int(scope)<<12))
        return None

    def service(self,segment_available=True):
        """Commit one offered word only when the actual transmit boundary accepts it."""
        _boolean(segment_available,'segment_available')
        message=self.offer()
        if not segment_available or message is None:return None
        if message.kind=='noop':
            self._noops-=1
            if self._noops==0:self._phase='request'
        elif message.kind=='request':
            self._phase='wait'
            self._deadline_ps=self._now_ps+self._TIMEOUT_PS
        else:
            self._responses.popleft()
        return message

    def advance_ps(self,elapsed):
        """Advance explicit nonnegative time; at deadline restart blocking/run-out.

        A large time jump causes one retry; another Request must actually be
        transmitted before a new response deadline can expire.
        """
        if type(elapsed) is not int or elapsed<0:raise ValueError('elapsed must be nonnegative integer picoseconds')
        self._now_ps+=elapsed
        if self._phase=='wait' and self._now_ps>=self._deadline_ps:
            self._retries+=1
            self._start_runout()

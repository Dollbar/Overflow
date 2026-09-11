"""Complete staged payload ownership around the independently checked sender.

Common2.0 normal Request/OrigData subset only. Request payload width is an
explicit local choice, not a standard wire packing. All data is ready before
acceptance. Invalid model edges are rejected atomically, not RTL recovery policy.
"""
from copy import deepcopy
from dataclasses import dataclass

from .upli_burst import BurstEvents, BurstRequest, UpliBurstSender


@dataclass(frozen=True)
class OrigDataPayload:
    data: int
    byte_enable: int
    error: bool


@dataclass(frozen=True)
class StagedBurst:
    request: BurstRequest
    request_payload: int
    data: tuple[OrigDataPayload, ...] = ()


@dataclass(frozen=True)
class BurstPayloadEvents:
    control: BurstEvents
    request_payload: int | None
    data_payload: OrigDataPayload | None


class UpliBurstPayload:
    """One immutable accepted tail per port; actual credits debit emitted beats.

    This is a reference composition, not another implementation of admission or
    TDM. Payload ownership is stored independently as remaining immutable tuples.
    """

    def __init__(self, capacities, num_ports, *, request_width, init_stable_cycles=2):
        if type(request_width) is not int:
            raise TypeError("opaque request width must be an integer")
        if request_width < 1:
            raise ValueError("opaque request width must be positive")
        self.request_width = request_width
        self._control = UpliBurstSender(capacities, num_ports, init_stable_cycles)
        self._pending: dict[int, tuple[OrigDataPayload, ...]] = {}

    @property
    def next_port(self):
        return self._control.next_port

    def balance(self, account):
        return self._control.balance(account)

    def reserved(self, account):
        return self._control.reserved(account)

    def available(self, account):
        return self._control.available(account)

    def initialized(self, port, channel):
        return self._control.initialized(port, channel)

    def _validate_payload(self, candidate):
        if not isinstance(candidate, StagedBurst) or not isinstance(candidate.request, BurstRequest):
            raise TypeError("a complete immutable StagedBurst candidate is required")
        if type(candidate.request_payload) is not int:
            raise TypeError("opaque request payload must be an integer")
        if not 0 <= candidate.request_payload < (1 << self.request_width):
            raise ValueError("opaque request payload exceeds configured width")
        if not isinstance(candidate.data, tuple):
            raise TypeError("all staged beats must be an immutable tuple")
        count = 0 if candidate.request.num_beats is None else candidate.request.num_beats + 1
        if len(candidate.data) != count:
            raise ValueError("exactly the declared complete payload must be staged")
        for word in candidate.data:
            if not isinstance(word, OrigDataPayload):
                raise TypeError("each staged beat must carry data, byte enable and error")
            for field, width in ((word.data,512),(word.byte_enable,64)):
                if type(field) is not int:
                    raise TypeError("data and byte-enable fields must be integers")
                if not 0 <= field < (1 << width):
                    raise ValueError("OrigData payload field exceeds its native width")
            if type(word.error) is not bool:
                raise TypeError("OrigData Error must be boolean")

    def step(self, connection, candidate=None, returns=(), init_done=(), reset=False):
        """Emit a complete current-edge event; no ownership of declined candidates.

        Reset has priority over malformed transaction inputs. A rejected normal
        edge leaves both credit/control and all pending payload unchanged.
        """
        if type(reset) is not bool:
            raise TypeError("reset must be boolean")
        if reset:
            control = self._control.step(None, reset=True)
            self._pending = {}
            return BurstPayloadEvents(control,None,None)
        if candidate is not None:
            self._validate_payload(candidate)
        control_sender = deepcopy(self._control)
        control = control_sender.step(connection, request=candidate.request if candidate else None,
                                      returns=returns, init_done=init_done)
        pending = dict(self._pending)
        request_payload = candidate.request_payload if control.accepted else None
        data_payload = None
        starts_data = control.accepted and candidate.request.num_beats is not None
        if starts_data:
            port = candidate.request.port
            if port in pending or control.data is None or control.data.offset != 0:
                raise RuntimeError("control does not transfer a free complete payload on its first beat")
            data_payload = candidate.data[0]
            if len(candidate.data) > 1:
                pending[port] = candidate.data[1:]
        elif control.data is not None:
            port = control.data.port
            remaining = pending.get(port)
            if not remaining or control.data.offset == 0 or control.data.last != (len(remaining) == 1):
                raise RuntimeError("control tail disagrees with independently held payload ownership")
            data_payload = remaining[0]
            if len(remaining) == 1:
                del pending[port]
            else:
                pending[port] = remaining[1:]
        self._control, self._pending = control_sender, pending
        return BurstPayloadEvents(control,request_payload,data_payload)

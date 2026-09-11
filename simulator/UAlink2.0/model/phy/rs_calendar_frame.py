"""Independent local composition of RS calendar and complete80-block frame.

DL/PL2.0 sections3.3.2 and3.3.5-3.3.7 define codeword alignment/calendar.
Reservation, payload transfers and completed codewords are distinct. Phase load
cancels local work and captures established configuration; it is not link wakeup
or permission to pause PCS. Steady RAM has no scheduled AM and uses count0xff.
The producer supplies every reserved640-byte frame; this model does not buffer
it or fabricate NOPs.

Run: python3 [-O] -m unittest verification.model.test_rs_calendar_frame -v
Output: cycle checks. Next: actual three-module RTL integration.
"""
from dataclasses import dataclass
from .rs_frame_control import FrameCommand, FrameEngine, FrameOutputs
from .rs_rate_calendar import tx_codeword_kind


@dataclass(frozen=True)
class CalendarConfig:
    phase: int
    rapid: bool = False
    resiliency: bool = False
    pl_id: int = 0

    def __post_init__(self):
        if type(self.phase) is not int or not 0 <= self.phase < 16384:
            raise ValueError('phase must fit an unsigned14-bit bus')
        if type(self.rapid) is not bool or type(self.resiliency) is not bool:
            raise ValueError('rapid and resiliency must be explicit booleans')
        if type(self.pl_id) is not int or self.pl_id not in (0, 1):
            raise ValueError('pl_id must be an integer0 or1')


@dataclass(frozen=True)
class CalendarOutputs:
    phase: int
    next_phase: int
    next_kind: str | None
    flit_ready: bool
    flit_reserved: bool
    frame: FrameOutputs
    codeword_completed: bool
    dl_completed: bool
    starved: bool


class CalendarFrame:
    """Pure pre-edge outputs followed by one synchronous state transition.

    phase exposes the current register even during reset/load, like the actual
    rate scheduler. next_kind is None during either suppression event.
    flit_ready qualifies descriptor admission only. starved reports a missing
    DL descriptor at an available boundary, or missing payload when an active
    Data frame is requested by ready. data=None means payload valid is low.
    """
    def __init__(self, serial_gbps, lanes, blocks_per_group):
        tx_codeword_kind(serial_gbps, lanes, 0)
        self.serial_gbps = serial_gbps
        self.lanes = lanes
        self._frame = FrameEngine(blocks_per_group)
        self._phase = 0
        self._config = CalendarConfig(0)

    def _evaluate(self, *, flit_valid=False, data=None, ready=True,
                  reset=False, phase_load=None):
        if type(flit_valid) is not bool:
            raise ValueError('flit_valid must be an explicit boolean')
        if type(reset) is not bool or type(ready) is not bool:
            raise ValueError('reset and ready must be explicit booleans')
        if phase_load is not None and type(phase_load) is not CalendarConfig:
            raise ValueError('phase_load must be a CalendarConfig or None')
        suppressed = reset or phase_load is not None
        current = self._frame.outputs(data=data, ready=ready, reset=suppressed)
        future_phase = (self._phase + int(current.frame_completed)) % 16384
        kind = None if suppressed else tx_codeword_kind(
            self.serial_gbps, self.lanes, future_phase,
            rapid_alignment=self._config.rapid)
        command = None
        if kind == 'dl_flit' and flit_valid:
            command = FrameCommand()
        elif kind is not None and kind != 'dl_flit':
            marker = {'alignment_marker':1, 'rapid_alignment_marker':2, 'rate_idle':0}[kind]
            command = FrameCommand(1, marker, 255 if marker == 2 else 0,
                                   self._config.resiliency, self._config.pl_id)
        frame = self._frame.outputs(command=command, data=data, ready=ready, reset=suppressed)
        flit_ready = frame.command_ready and kind == 'dl_flit'
        data_frame = frame.active and frame.metadata.kind == 0
        starved = (flit_ready and not flit_valid) or (data_frame and ready and data is None)
        return CalendarOutputs(self._phase, future_phase, kind, flit_ready,
            flit_ready and frame.command_accepted, frame, frame.frame_completed,
            frame.frame_completed and data_frame, starved), command

    def outputs(self, *, flit_valid=False, data=None, ready=True,
                reset=False, phase_load=None):
        return self._evaluate(flit_valid=flit_valid, data=data, ready=ready,
                              reset=reset, phase_load=phase_load)[0]

    def tick(self, *, flit_valid=False, data=None, ready=True,
             reset=False, phase_load=None):
        out, command = self._evaluate(flit_valid=flit_valid, data=data, ready=ready,
                                      reset=reset, phase_load=phase_load)
        self._frame.tick(command=command, data=data, ready=ready,
                         reset=reset or phase_load is not None)
        if reset:
            self._phase = 0
            self._config = CalendarConfig(0)
        elif phase_load is not None:
            self._phase = phase_load.phase
            self._config = phase_load
        elif out.codeword_completed:
            self._phase = out.next_phase
        return out

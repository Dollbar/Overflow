"""Cycle reference for an80-block RS transmit frame engine with held metadata.

UALink DL/PL2.0 sections3.2.2-3.2.4 define complete consecutive block sequences.
The command/data/output handshakes below are a local implementation interface,
not permission to stall a physical PCS stream. Command acceptance reserves held
metadata; frame_completed is asserted only on the actual last output transfer.
Count policy, link-state transitions and calendar lookahead belong upstream.

Run: python3 [-O] -m unittest verification.model.test_rs_frame_control -v
Output: cycle-reference checks. Next: actual controller and real formatter RTL.
"""
from dataclasses import dataclass
from . import rs_block_codec as codec


@dataclass(frozen=True)
class FrameCommand:
    kind: int = 0
    marker: int = 0
    count: int = 0
    resiliency: bool = False
    pl_id: int = 0


@dataclass(frozen=True)
class FrameOutputs:
    active: bool
    command_ready: bool
    command_accepted: bool
    command_rejected: bool
    data_ready: bool
    data_consumed: bool
    output_valid: bool
    output_taken: bool
    last: bool
    frame_completed: bool
    index: int
    metadata: FrameCommand | None
    blocks: tuple


def _check_command(command):
    if not isinstance(command, FrameCommand):
        raise ValueError('expected a FrameCommand or None')
    for name, width in (('kind', 3), ('marker', 2), ('count', 8), ('pl_id', 1)):
        value = getattr(command, name)
        if type(value) is not int or not 0 <= value < 2**width:
            raise ValueError(f'{name} must fit its unsigned{width}-bit input bus')
    if type(command.resiliency) is not bool:
        raise ValueError('resiliency must be an explicit boolean')


def _legal(command):
    return (command.kind < 5 and command.marker < 3
            and not (command.kind == 0 and command.marker != 0)
            and not (command.kind == 4 and command.marker == 2))


class FrameEngine:
    """Pure output evaluation followed by one synchronous reference transition.

    None command/data means the corresponding input valid is low. Data is one
    group of8*N bytes with the earliest block first. A data producer must hold
    its valid payload until consumed; this engine stores metadata, not payload.
    A rejected command consumes the ready command slot but starts no frame.
    Reset cancels current work without claiming completion or accepting inputs.
    """
    def __init__(self, blocks_per_group):
        if type(blocks_per_group) is not int or blocks_per_group not in (1, 2, 4, 8):
            raise ValueError('blocks_per_group must be1,2,4 or8')
        self.blocks_per_group = blocks_per_group
        self.active = False
        self.index = 0
        self.metadata = FrameCommand()

    def outputs(self, *, command=None, data=None, ready=True, reset=False):
        if command is not None:
            _check_command(command)
        if data is not None and (type(data) is not bytes or len(data) != 8*self.blocks_per_group):
            raise ValueError('data must contain exactly8*N bytes or be None')
        if type(ready) is not bool or type(reset) is not bool:
            raise ValueError('ready and reset must be explicit booleans')
        if reset:
            return FrameOutputs(active=False, command_ready=False,
                command_accepted=False, command_rejected=False, data_ready=False,
                data_consumed=False, output_valid=False, output_taken=False,
                last=False, frame_completed=False, index=0, metadata=None, blocks=())

        is_data = self.metadata.kind == 0
        valid = self.active and (not is_data or data is not None)
        last = valid and self.index == 80-self.blocks_per_group
        taken = valid and ready
        completed = taken and last
        command_ready = not self.active or completed
        accepted = command_ready and command is not None and _legal(command)
        rejected = command_ready and command is not None and not _legal(command)
        blocks = ()
        if valid:
            if is_data:
                blocks = tuple(codec.encode_block('data', data[i:i+8])
                               for i in range(0, len(data), 8))
            else:
                codes = codec.encode_control_flit(
                    {1:'idle', 2:'local_fault', 3:'remote_fault', 4:'power_down'}[self.metadata.kind],
                    marker={0:None, 1:'am', 2:'ram'}[self.metadata.marker],
                    am_next_count=self.metadata.count if self.metadata.marker == 2 else None,
                    link_resiliency=self.metadata.resiliency, pl_id=self.metadata.pl_id)
                blocks = codes[self.index:self.index+self.blocks_per_group]
        return FrameOutputs(active=self.active, command_ready=command_ready,
            command_accepted=accepted, command_rejected=rejected,
            data_ready=self.active and is_data and ready,
            data_consumed=taken and is_data, output_valid=valid, output_taken=taken,
            last=last, frame_completed=completed, index=self.index if self.active else 0,
            metadata=self.metadata if self.active else None, blocks=blocks)

    def tick(self, *, command=None, data=None, ready=True, reset=False):
        """Return pre-edge outputs and then apply exactly one reference clock edge."""
        result = self.outputs(command=command, data=data, ready=ready, reset=reset)
        if reset:
            self.active = False
            self.index = 0
            self.metadata = FrameCommand()
        elif result.command_accepted:
            self.active = True
            self.index = 0
            self.metadata = command
        elif result.frame_completed:
            self.active = False
            self.index = 0
        elif result.output_taken:
            self.index += self.blocks_per_group
        return result

"""Local sufficient FIFO budget and atomic consumption/credit handoff.
The budget covers the confirmed command tenure profile, not all future opcodes.
"""
def required_words(capacities):
    return 2*sum(capacities)


def configuration_valid(capacities, *, width, depth, shared):
    if type(width) is not int or not 1<=width<=16:return False
    if type(depth) is not int or not 1<=depth<=65535:return False
    if len(capacities)!=20 or any(type(v) is not int or not 0<=v<(1<<width) for v in capacities):return False
    if not shared and (not any(capacities[10:15]) or not any(capacities[15:20])):return False
    return required_words(capacities)<=depth


def retirement(valid, ready, credit_ready, fatal):
    read_valid=bool(valid and credit_ready and not fatal)
    taken=bool(read_valid and ready)
    return dict(read_valid=read_valid,retired=taken,release_taken=taken)

"""Independent fixed-width bit population oracle, not an RTL/helper invocation."""
import random

def parity(value):
    return value.bit_count() & 1

def expected(enable, valid, pool, vc, num, init, received_valid, received_control):
    valid_parity=parity(valid)
    control_parity=parity((pool<<16)|(vc<<8)|num)
    ve=int(bool(enable) and valid_parity!=received_valid)
    ce=int(bool(enable) and bool(valid) and control_parity!=received_control)
    return valid,pool,vc,num,init,valid_parity,control_parity,ve,ce,ve|ce,int(not(ve|ce))

def vectors():
    rng=random.Random(431421)
    rows=[]
    # The first vector rejects a zero-output adapter and a fail-closed guard.
    seeds=[(1,1,0,0,0,15,0,0),(1,0,0,0,0,0,1,1)]
    for valid in range(16):
        # Every individual protected control bit, including inactive-port fields.
        for bit in range(20):
            fields=1<<bit
            for enable in (0,1):
                for corruption in range(4):
                    pool=(fields>>16)&15;vc=(fields>>8)&255;num=fields&255
                    seeds.append((enable,valid,pool,vc,num,rng.randrange(16),parity(valid)^(corruption&1),parity(fields)^((corruption>>1)&1)))
        for init in range(16):
            seeds.append((1,valid,10,228,27,init,parity(valid),parity((10<<16)|(228<<8)|27)))
    for _ in range(600):
        seeds.append((rng.randrange(2),rng.randrange(16),rng.randrange(16),rng.randrange(256),rng.randrange(256),rng.randrange(16),rng.randrange(2),rng.randrange(2)))
    for seed in seeds:rows.append(seed+expected(*seed))
    return rows

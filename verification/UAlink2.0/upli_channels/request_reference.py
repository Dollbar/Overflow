"""Independent native Request field/parity oracle; no RTL implementation imports."""
FIELDS=(('asi',2),('auth_tag',64),('src',10),('dst',10),('tag',11),('num_beats',2),('address',57),('command',6),('length',6),('attr',8),('metadata',8),('port',2),('vc',2),('pool',1))
def encode(fields):
    word=0
    for name,width in FIELDS:
        value=fields[name]
        if not 0<=value<(1<<width):raise ValueError(name)
        word=(word<<width)|value
    return word

def parity(value):
    # Byte-wise counting is independent of the RTL reduction expression.
    return sum(byte.bit_count() for byte in value.to_bytes((value.bit_length()+7)//8,'little'))%2

def observe(rstn,valid,fields):
    if not rstn or not valid:return (0,0,0,0,0,0)
    control=sum(parity(fields[n]) for n,_ in FIELDS if n not in ('auth_tag','address'))%2
    return (1,encode(fields),1,parity(fields['auth_tag']),parity(fields['address']),control)

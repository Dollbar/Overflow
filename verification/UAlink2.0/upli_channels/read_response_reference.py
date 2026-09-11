"""Native RdRsp wire oracle; independent byte counting, no RTL/model imports."""
FIELDS=(('port',2),('auth_tag',64),('src',10),('dst',10),('tag',11),('num_beats',2),('data',512),('status',4),('offset',2),('last',1),('data_error',1),('type_info',2),('vc',2),('pool',1))
def pack(fields):
 result=0
 for name,width in FIELDS:
  value=fields[name]
  if type(value) is not int or not 0<=value<(1<<width):raise ValueError(name)
  result=result*(1<<width)+value
 return result

def even(value,width):
 return sum(byte.bit_count() for byte in value.to_bytes((width+7)//8,'little'))%2

def expected(rstn,valid,fields):
 if not rstn or not valid:return (0,0,0,0,0,0)
 controls=sum(even(fields[n],w) for n,w in FIELDS if n not in ('data','auth_tag'))%2
 data_parity=sum(even((fields['data']>>(64*lane))&((1<<64)-1),64)<<lane for lane in range(8))
 return (1,pack(fields),1,even(fields['auth_tag'],64),data_parity,controls)

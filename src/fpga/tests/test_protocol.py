import sys,struct,socket
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from udp_monitor import parse,FMT
assert struct.calcsize(FMT)==40
pl=struct.pack(FMT,b'FPGA',1,0x08,2,0,7,111250,8,3,-10,25001,13000,4,77,0x54454332)
p=parse(pl)
assert p['frequency_hz']==111250 and p['temperature_c']==25.001
assert p['dac_code']==-10 and p['virtual_temperature']

# Confirm static IPv4 header checksum for the FPGA default addresses.
header=bytes.fromhex('4500 0044 0000 4000 4011 b64f c0a8 010a c0a8 01ff')
s=sum(int.from_bytes(header[i:i+2],'big') for i in range(0,20,2))
while s>0xffff:s=(s&0xffff)+(s>>16)
assert s == 0xffff,hex(s)
print('PASS python payload format & IPv4 header checksum')

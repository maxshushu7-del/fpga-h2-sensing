#!/usr/bin/env python3
"""Validates expected XSim Ethernet/IPv4/UDP/FCS frame reference (not RTL execution)."""
from pathlib import Path
import re,struct,binascii
R=Path(__file__).resolve().parents[1]
s=(R/'sim/tb_udp_ipv4_frame_tx.sv').read_text()
pl=bytes.fromhex(re.search(r"320'h([A-Fa-f0-9]+)",s).group(1))
assert len(pl)==40
srcip=bytes([192,168,1,10]); dstip=bytes([192,168,1,255])
ip=bytearray.fromhex('450000440000400040110000')+bytearray(srcip+dstip)
w=sum(int.from_bytes(ip[i:i+2],'big') for i in range(0,20,2))
while w>65535:w=(w&65535)+(w>>16)
ip[10:12]=struct.pack('!H',~w&65535)
frame=bytes([255]*6)+bytes.fromhex('0215660000010800')+ip+struct.pack('!HHHH',5000,5001,48,0)+pl
allbytes=b'\x55'*7+b'\xd5'+frame+binascii.crc32(frame).to_bytes(4,'little')
assert len(allbytes)==94
rows=re.findall(r"^\s*(\d+): expected_byte=8'h([0-9A-Fa-f]{2});",s,re.M)
assert len(rows)==94,len(rows)
for (i,h),b in zip(rows,allbytes):
    assert int(i)==rows.index((i,h)),i
    assert int(h,16)==b, (i,h,b)
assert 'tx_byte !== expected_byte(seen)' in s
print('PASS: golden full 94-byte UDP Ethernet+IPv4 checksum+CRC32/FCS test vectors')

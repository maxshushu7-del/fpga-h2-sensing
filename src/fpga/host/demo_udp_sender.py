#!/usr/bin/env python3
"""PC-only demonstration of the 40-byte telemetry format (NOT FPGA data)."""
import socket, struct, time
from udp_monitor import FMT
sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
print('PC synthetic demonstration -> 127.0.0.1:5001. Ctrl+C to stop.')
seq=0
while True:
    p=struct.pack(FMT,b'FPGA',1,8,0,0,seq,100000+seq,seq,
                  3,0,25000+(seq%100)*10,5000,4,seq,0x54454332)
    sock.sendto(p,('127.0.0.1',5001))
    seq+=1
    time.sleep(0.1)

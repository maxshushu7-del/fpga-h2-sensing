"""Optional UDP loopback TEST FIXTURES. Not a live FPGA source.

This script is never started by the dashboard and is only provided to check
binary datagram decoding, ADC chunk reassembly and Windows firewall settings.
"""
from __future__ import annotations
import argparse
import math
import socket
import struct
import time
from udp_protocol import HEADER, TELEM, RAW, CHUNK, MAX_CHUNK_SAMPLES


def packet(kind, payload, seq, ms):
    return HEADER.pack(b'H2PK',1,kind,len(payload),seq,ms)+payload


def telemetry(seq, frequency_hz=33_000_000):
    flags=0x01|0x02|0x04|0x08|0x10|0x20|0x40|0x80
    body=TELEM.pack(12,flags,0,600_000,1_208_000,1_200,30_012,30_000,62,frequency_hz)
    return packet(1,body,seq,seq*100)


def raw_telemetry(seq):
    return packet(3,RAW.pack(12,0x01|0x02|0x08|0x40|0x80,0,8500,-12,33_000_000),seq,seq*100)


def adc_packets(capture_id, hz=33e6, rate=250_000_000, samples=4096):
    # Only a software communication test signal, not experimentally acquired.
    from math import sin,pi
    ys=[int(4500*sin(2*pi*hz*n/rate)) for n in range(samples)]
    count=(samples+MAX_CHUNK_SAMPLES-1)//MAX_CHUNK_SAMPLES
    result=[]
    for idx in range(count):
        sub=ys[idx*MAX_CHUNK_SAMPLES:(idx+1)*MAX_CHUNK_SAMPLES]
        payload=CHUNK.pack(capture_id,idx,count,rate,len(sub),samples)
        payload+=struct.pack('<%dh'%len(sub),*sub)
        result.append(packet(2,payload,capture_id,100*capture_id))
    return result


def main():
    ap=argparse.ArgumentParser(description='UDP protocol loopback tester only')
    ap.add_argument('--host',default='127.0.0.1',help='LOCAL LOOPBACK by default')
    ap.add_argument('--port',type=int,default=5001)
    ap.add_argument('--count',type=int,default=20)
    args=ap.parse_args()
    s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    dest=(args.host,args.port)
    for i in range(max(1,args.count)):
        s.sendto(telemetry(i+1),dest)
        if i%5==0:
            for chunk in adc_packets(i+1):s.sendto(chunk,dest)
        time.sleep(.10)
    s.close()
    print('UDP loopback TEST packets transmitted. These are NOT FPGA measurements.')


if __name__=='__main__': main()

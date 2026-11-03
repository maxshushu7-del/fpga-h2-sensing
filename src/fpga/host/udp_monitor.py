#!/usr/bin/env python3
"""Listen to the fixed-format FPGA UDP telemetry on port 5001.
No third-party dependencies. Demo FPGA IP 192.168.1.10 -> 192.168.1.255.
"""
import argparse, socket, struct, datetime

FMT = '>4sBBBBIIIhh iHHII'.replace(' ', '')
assert struct.calcsize(FMT) == 40, struct.calcsize(FMT)

def parse(data):
    if len(data)!=40:
        raise ValueError(f'expected 40 UDP payload bytes, got {len(data)}')
    (magic,version,flags,state,fault,seq,frequency,fftseq,
     error,dac,temp_mc,duty,temp_flags,uptime,tail)=struct.unpack(FMT,data)
    if magic!=b'FPGA' or tail!=0x54454332:
        raise ValueError('wrong magic / tail')
    return dict(version=version,flags=flags,auto_state=state,
                auto_fault=fault,seq=seq,frequency_hz=frequency,
                fft_seq=fftseq,laser_error=error,dac_code=dac,
                temperature_c=temp_mc/1000,duty=duty,
                temp_fault=bool(temp_flags&1),temp_pwm=bool(temp_flags&2),
                **{'virtual_temperature':bool(temp_flags&4)},uptime_10ms=uptime)

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--port',type=int,default=5001)
    p.add_argument('--bind',default='0.0.0.0')
    args=p.parse_args()
    sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    sock.bind((args.bind,args.port))
    print(f'AXAU15 V4 Ethernet UDP receiver on {args.bind}:{args.port} (Ctrl+C to quit)')
    while True:
        data,addr=sock.recvfrom(2048)
        try:
            p=parse(data)
            print(datetime.datetime.now().strftime('%H:%M:%S.%f')[:-3],addr,
                  f"seq={p['seq']} FFT={p['frequency_hz']}Hz temp={p['temperature_c']:.3f}C",
                  f"PID_duty={p['duty']} fault={p['temp_fault']} DEMO={p['virtual_temperature']}")
        except ValueError as e:
            print(f'Ignored packet from {addr}: {e}')

if __name__=='__main__':
    main()

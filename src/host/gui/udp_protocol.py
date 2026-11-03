"""Native Ethernet UDP datagram payloads for FPGA H2 telemetry.

No serial stream framing or transport compatibility. Input is exactly one UDP
 datagram containing either a native H2PK v1 packet or a UTF-8 JSON record.

Header: <4sBBHII: magic=b'H2PK', version=1, kind, payload_bytes, seq, ms.
Kind 1: calibrated instrument telemetry (32-byte payload).
Kind 2: bounded ADC capture chunk (16 + 2*N bytes payload, <=512 samples).
Kind 3: raw-code telemetry for an FPGA without voltage calibration.
JSON telemetry is useful for development and Ethernet-capable controllers.
"""
from __future__ import annotations
import json
import math
import struct
from typing import Dict, List

MAGIC=b'H2PK'
VERSION=1
HEADER=struct.Struct('<4sBBHII')
TELEM=struct.Struct('<BBHiiiiiiI')  # 32 bytes
RAW=struct.Struct('<BBHiiI')         # 16 bytes
CHUNK=struct.Struct('<IHHIHH')       # 16 bytes
V4=struct.Struct('>4sBBBBIIIhhiHHII') # AXAU15 FPGA/TEC2, 40-byte big-endian payload
MAX_UDP=65507
MAX_SAMPLES=4096
MAX_CHUNK_SAMPLES=512
STATES={
    0:'待机',1:'粗扫初始化',2:'粗扫描',3:'粗扫描',4:'粗扫识别',
    5:'粗扫回程',6:'细扫初始化',7:'精细扫描',8:'精细扫描',
    9:'细扫识别',10:'定位锁点',11:'反馈准备',12:'已锁定',13:'异常'
}


def _number(obj, key, low=None, high=None):
    if key not in obj or obj[key] is None: return None
    v=obj[key]
    if isinstance(v,bool) or not isinstance(v,(int,float)):
        raise ValueError('not numeric: '+key)
    v=float(v)
    if not math.isfinite(v) or (low is not None and v<low) or (high is not None and v>high):
        raise ValueError('numeric value out of range: '+key)
    return v


def _json(obj):
    if not isinstance(obj,dict): raise ValueError('JSON record must be an object')
    kind=obj.get('type','telemetry')
    if kind not in ('telemetry','status','fft_result','temperature','adc_samples','spectrum'):
        raise ValueError('JSON record type unsupported')
    out={'type':kind}
    if 'seq' in obj:
        seq=obj['seq']
        if type(seq) is not int or not 0<=seq<2**32: raise ValueError('invalid seq')
        out['seq']=seq
    if kind in ('telemetry','status'):
        if 'locked' in obj:
            if type(obj['locked']) is not bool: raise ValueError('locked must be bool')
            out['locked']=obj['locked']
        if 'state' in obj:
            if not isinstance(obj['state'],str) or len(obj['state'])>64:
                raise ValueError('invalid state')
            out['state']=obj['state']
        for key,low,high in [('da_v',-20,20),('pd_v',-20,20),('error_mv',-10000,10000),
                             ('dac_code',-2147483648,2147483647),('error_code',-2147483648,2147483647)]:
            v=_number(obj,key,low,high)
            if v is not None: out[key]=v
    if kind in ('telemetry','fft_result'):
        v=_number(obj,'frequency_hz',0,1_200_000_000)
        if v is not None: out['frequency_hz']=v
        if 'frequency_valid' in obj:
            if type(obj['frequency_valid']) is not bool:
                raise ValueError('frequency_valid must be bool')
            out['frequency_valid']=obj['frequency_valid']
    if kind in ('telemetry','temperature'):
        for key,low,high in [('temperature_c',-100,200),('temperature_target_c',-100,200),
                             ('heater_duty_pct',0,100)]:
            v=_number(obj,key,low,high)
            if v is not None:out[key]=v
    if kind=='adc_samples':
        samples=obj.get('samples')
        if not isinstance(samples,list) or not 16<=len(samples)<=MAX_SAMPLES:
            raise ValueError('invalid adc sample count')
        if any(type(v) not in (int,float) or not math.isfinite(v) or v<-32768 or v>32767 for v in samples):
            raise ValueError('invalid adc sample')
        out['samples']=samples
        out['sample_rate_hz']=_number(obj,'sample_rate_hz',1,500_000_000)
        if out['sample_rate_hz'] is None: raise ValueError('missing sample_rate_hz')
        out['channel']=int(obj.get('channel',1))
    if kind=='spectrum':
        bins=obj.get('dbfs')
        if not isinstance(bins,list) or not 16<=len(bins)<=4097:
            raise ValueError('invalid spectrum bins')
        if any(type(v) not in (float,int) or not math.isfinite(v) or v<-240 or v>80 for v in bins):
            raise ValueError('invalid spectrum bin')
        out['dbfs']=bins
        for key in ('start_hz','bin_hz'):
            out[key]=_number(obj,key,0,1_000_000_000)
            if out[key] is None: raise ValueError('missing '+key)
    return out


def parse_packet(data: bytes)->List[Dict]:
    """Parse a UDP datagram. Reject malformed payloads as a whole."""
    if not data or len(data)>MAX_UDP:raise ValueError('invalid datagram size')
    if data.startswith(b'FPGA'):
        if len(data)!=V4.size:raise ValueError('V4 payload must contain exactly 40 bytes')
        (magic,version,flags,state,fault,seq,freq,fftseq,error,dac,
         temp_mc,duty,temp_flags,ticks,tail)=V4.unpack(data)
        if version!=1 or tail!=0x54454332:raise ValueError('V4 version/tail mismatch')
        if state not in STATES:raise ValueError('V4 state unsupported')
        if flags & 0x84 or temp_flags & ~0x07:raise ValueError('V4 reserved flag bits')
        initialized=bool(flags&0x10) and bool(flags&0x20)
        temperature_model=bool(temp_flags&4)
        # The RTL transmits raw DAC/error codes, not calibrated voltages or PD samples.
        status=dict(type='telemetry',protocol='FPGA_V4',seq=seq,
                    timestamp_ms=ticks*10,state=STATES[state],
                    locked=(state==12 and fault==0 and initialized),fault=fault,
                    dac_code=dac,error_code=error,temperature_c=temp_mc/1000,
                    heater_duty_pct=(100.0 if duty==65535 else 100.0*duty/65536),
                    temperature_model=temperature_model,
                    temperature_fault=bool(temp_flags&1) or bool(flags&2),
                    temperature_pwm=bool(temp_flags&2),fft_enabled=bool(flags&0x40))
        # A network snapshot and an FFT result have different sequence counters.
        fft=dict(type='fft_result',protocol='FPGA_V4',seq=fftseq,
                 timestamp_ms=ticks*10,frequency_hz=freq,
                 frequency_valid=bool(flags&1) and bool(flags&0x40) and initialized)
        return [status,fft]
    if data.lstrip().startswith((b'{',b'[')):
        try: obj=json.loads(data.decode('utf-8'))
        except (ValueError,UnicodeDecodeError) as exc: raise ValueError('malformed JSON') from exc
        records=obj if isinstance(obj,list) else [obj]
        if not 1<=len(records)<=12: raise ValueError('invalid JSON record count')
        return [_json(x) for x in records]
    if len(data)<HEADER.size:raise ValueError('native UDP header too short')
    magic,version,kind,nbytes,seq,timestamp_ms=HEADER.unpack_from(data)
    if magic!=MAGIC or version!=VERSION:raise ValueError('invalid H2PK magic/version')
    if nbytes!=len(data)-HEADER.size:raise ValueError('UDP payload length mismatch')
    payload=data[HEADER.size:]
    base=dict(seq=seq,timestamp_ms=timestamp_ms)
    if kind==1:
        if len(payload)!=TELEM.size:raise ValueError('telemetry payload size')
        state,flags,reserved,da_uv,pd_uv,error_uv,temp_mc,target_mc,heater_permille,freq_hz=TELEM.unpack(payload)
        if state not in STATES or reserved!=0:raise ValueError('telemetry state/reserved')
        out={**base,'type':'telemetry','state':STATES[state],'locked':bool(flags&1)}
        if flags&0x02:out['da_v']=da_uv/1e6
        if flags&0x04:out['pd_v']=pd_uv/1e6
        if flags&0x08:out['error_mv']=error_uv/1000
        if flags&0x10:
            out['temperature_c']=temp_mc/1000
            out['temperature_target_c']=target_mc/1000
        if flags&0x20:out['heater_duty_pct']=heater_permille/10
        if flags&0x40:
            out['frequency_hz']=freq_hz
            out['frequency_valid']=bool(flags&0x80)
        return [_json(out)]
    if kind==2:
        if len(payload)<CHUNK.size:raise ValueError('ADC chunk header short')
        capture,idx,count,fs,n,total=CHUNK.unpack_from(payload)
        if not 1<=total<=MAX_SAMPLES or not 1<=n<=MAX_CHUNK_SAMPLES:
            raise ValueError('ADC sample count')
        if not 1<=fs<=500_000_000 or count!=(total+MAX_CHUNK_SAMPLES-1)//MAX_CHUNK_SAMPLES:
            raise ValueError('ADC sample rate/chunk count')
        if idx>=count or n!=min(MAX_CHUNK_SAMPLES,total-idx*MAX_CHUNK_SAMPLES):
            raise ValueError('ADC chunk index/length')
        if len(payload)!=CHUNK.size+2*n:raise ValueError('ADC bytes length')
        samples=list(struct.unpack_from('<%dh'%n,payload,CHUNK.size))
        return [{**base,'type':'adc_chunk','capture_id':capture,'chunk_index':idx,
                 'chunk_count':count,'sample_rate_hz':fs,'total_samples':total,'samples':samples}]
    if kind==3:
        if len(payload)!=RAW.size:raise ValueError('raw telemetry payload size')
        state,flags,reserved,dac_code,error_code,freq_hz=RAW.unpack(payload)
        if state not in STATES or reserved!=0:raise ValueError('raw state/reserved')
        out={**base,'type':'telemetry','state':STATES[state],'locked':bool(flags&1)}
        if flags&0x02:out['dac_code']=dac_code
        if flags&0x08:out['error_code']=error_code
        if flags&0x40:
            out['frequency_hz']=freq_hz
            out['frequency_valid']=bool(flags&0x80)
        return [_json(out)]
    raise ValueError('unknown H2PK kind')

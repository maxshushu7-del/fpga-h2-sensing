"""UDP transport and live-only data model for the V6 FPGA H2 display.

This contains NO synthetic waveforms, no timed gas events, no fixed temperature
sequence. The model updates only when validated UDP packets arrive.
"""
from __future__ import annotations
import math
import queue
import socket
import threading
import time
from collections import deque

import numpy as np
from udp_protocol import parse_packet


class UDPListener:
    def __init__(self, max_queue=500):
        self.messages=queue.Queue(maxsize=max_queue)
        self.stop_event=threading.Event()
        self.thread=None
        self.sock=None
        self.endpoint=None
        self.bind_error=None
        self.decoded=0
        self.datagrams=0
        self.rejected=0
        self.dropped=0
        self.last_sender=None
        self._adc_parts={}  # (sender,capture_id) => short-lived UDP chunk reassembly

    def _push(self, entry):
        try: self.messages.put_nowait(entry)
        except queue.Full:
            self.dropped+=1
            try: self.messages.get_nowait()
            except queue.Empty: pass
            try: self.messages.put_nowait(entry)
            except queue.Full: pass

    def start(self, host='0.0.0.0', port=5001):
        self.stop()
        while not self.messages.empty():
            try:self.messages.get_nowait()
            except queue.Empty:break
        self.decoded=self.datagrams=self.rejected=self.dropped=0
        self.last_sender=None
        sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        sock.settimeout(.2)
        try:
            sock.bind((host,int(port)))
        except OSError as exc:
            sock.close()
            self.bind_error=str(exc)
            self.endpoint=None
            self._push(('error',str(exc),time.monotonic(),None))
            return False
        self.stop_event=threading.Event()
        self._adc_parts.clear()
        self.sock=sock
        self.endpoint=sock.getsockname()
        self.bind_error=None
        self.thread=threading.Thread(target=self._worker,args=(sock,self.stop_event),daemon=True)
        self.thread.start()
        return True

    def _worker(self,sock,stop_event):
        while not stop_event.is_set():
            try:
                data,sender=sock.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError:
                break
            ts=time.monotonic()
            try:
                packets=parse_packet(data)
            except (ValueError,TypeError,OverflowError,UnicodeError) as exc:
                self.rejected+=1
                self._push(('reject',str(exc),ts,sender))
                continue
            self.last_sender=sender
            self.datagrams+=1
            self.decoded+=len(packets)
            for pkt in packets:
                if pkt.get('type')=='adc_chunk':
                    complete=self._adc_reassemble(pkt, sender, ts)
                    if complete is not None:
                        self._push(('packet',complete,ts,sender))
                else:
                    self._push(('packet',pkt,ts,sender))

    def _adc_reassemble(self,pkt,sender,ts):
        # UDP datagrams may arrive out of order. Never expose incomplete ADC
        # captures as if they were a complete time-domain waveform.
        expired=[key for key,part in self._adc_parts.items() if ts-part['first']>2.0]
        for key in expired: del self._adc_parts[key]
        key=(sender,pkt['capture_id'])
        info=self._adc_parts.get(key)
        if info is None:
            if len(self._adc_parts)>=16:
                oldest=min(self._adc_parts, key=lambda k:self._adc_parts[k]['first'])
                del self._adc_parts[oldest]
            info=dict(first=ts, fs=pkt['sample_rate_hz'], count=pkt['chunk_count'],
                      total=pkt['total_samples'], chunks={})
            self._adc_parts[key]=info
        if (info['fs']!=pkt['sample_rate_hz'] or info['count']!=pkt['chunk_count']
                or info['total']!=pkt['total_samples']):
            del self._adc_parts[key]
            self.rejected+=1
            return None
        info['chunks'][pkt['chunk_index']]=pkt['samples']
        if len(info['chunks'])!=info['count']: return None
        signal=[]
        for idx in range(info['count']): signal.extend(info['chunks'][idx])
        del self._adc_parts[key]
        if len(signal)!=info['total']:
            self.rejected+=1
            return None
        return dict(type='adc_samples',seq=pkt['capture_id'],sample_rate_hz=info['fs'],
                    channel=1,samples=signal)

    def stop(self):
        self.stop_event.set()
        if self.sock is not None:
            try: self.sock.close()
            except OSError: pass
        if self.thread is not None and self.thread.is_alive():
            self.thread.join(timeout=.5)
        self.thread=None
        self.sock=None
        self.endpoint=None
        self._adc_parts.clear()

    def drain(self,limit=240):
        result=[]
        for _ in range(limit):
            try: result.append(self.messages.get_nowait())
            except queue.Empty: break
        return result


class LiveModel:
    """Single real-time source for both windows; never fills missing fields."""
    def __init__(self,cal):
        self.cal=cal
        self.baseline_mhz=1.0
        self.start_monotonic=time.monotonic()
        self.clear()

    def clear(self):
        self.start_monotonic=time.monotonic()
        self.t=0.
        self.state='等待锁定状态包'
        self.event='UDP 监听已启动；等待 FPGA 数据'
        self.locked=None
        self.fault=0
        self.da=np.nan
        self.dac_code=np.nan
        self.da_unit='code'
        self.has_da_volts=False
        self.has_error_mv=False
        self.last_da_v=None
        self.last_error_mv=None
        self.pd=np.nan
        self.err=np.nan
        self.error_unit='mV'
        self.err_filtered=np.nan
        self.measured_freq=np.nan
        self.measured_conc=np.nan
        self.current_shift_mhz=np.nan
        self.temperature_c=np.nan
        self.temperature_target_c=np.nan
        self.heater_duty_pct=np.nan
        self.beat_wave=np.array([],dtype=float)
        self.sample_rate_hz=None
        self.frequencies=np.array([],dtype=float)
        self.fft=np.array([],dtype=float)
        self.last_record=None
        self.last_any=None
        self.last_status=None
        self.last_pd_v=None
        self.last_fft=None
        self.last_temperature=None
        self.last_wave=None
        self.last_spec=None
        self.status_seq=None
        self.fft_seq=None
        self.fft_quality=None
        self.temperature_source='等待温度数据'
        self.temperature_fault=False
        self.status_packets=0
        self.fft_packets=0
        self.invalid_fft=0
        self.messages=0
        self.t_hist=deque(maxlen=10000)
        self.da_hist=deque(maxlen=10000)
        self.pd_hist=deque(maxlen=10000)
        self.err_hist=deque(maxlen=10000)
        self.filtered_err_hist=deque(maxlen=10000)
        self.temp_hist=deque(maxlen=10000)
        self.c_hist=deque(maxlen=10000)
        self.beat_hist=deque(maxlen=10000)
        self.response_elapsed_hist=deque(maxlen=20000)
        self.response_shift_hist=deque(maxlen=20000)
        self.response_conc_hist=deque(maxlen=20000)
        self.response_start=None
        self.audit=deque(maxlen=15000)
        self.sender='—'
        self.network_status='等待 UDP 数据'
        self.last_error=''

    def _time(self,rx):
        return max(0.,rx-self.start_monotonic)

    def _log_data(self,ts,source):
        self.t_hist.append(ts)
        self.da_hist.append(self.da if self.last_status is not None else np.nan)
        self.pd_hist.append(self.pd if self.last_status is not None else np.nan)
        self.err_hist.append(self.err if self.last_status is not None else np.nan)
        self.filtered_err_hist.append(self.err_filtered if self.last_status is not None else np.nan)
        self.temp_hist.append(self.temperature_c)
        self.c_hist.append(self.measured_conc)
        self.beat_hist.append(self.measured_freq)
        self.audit.append((ts,source,self.state,self.da,self.pd,self.err,
                          self.measured_freq,self.current_shift_mhz,self.measured_conc,
                          self.temperature_c,self.heater_duty_pct))

    def _switch_da_unit(self,new_unit):
        if self.da_unit!=new_unit:
            self.da_unit=new_unit
            self.da_hist=deque([np.nan]*len(self.da_hist),maxlen=10000)
            self.da=np.nan

    def _switch_error_unit(self,new_unit):
        if self.error_unit!=new_unit:
            self.error_unit=new_unit
            self.err_hist=deque([np.nan]*len(self.err_hist),maxlen=10000)
            self.filtered_err_hist=deque([np.nan]*len(self.filtered_err_hist),maxlen=10000)
            self.err=np.nan
            self.err_filtered=np.nan

    def _update_feedback(self):
        if not np.isfinite(self.err):
            self.err_filtered=np.nan
        else:
            self.err_filtered=self.err if not np.isfinite(self.err_filtered) else (.22*self.err+.78*self.err_filtered)

    def _update_frequency(self,frequency_hz,ts,valid=True):
        if not valid or frequency_hz is None or frequency_hz <= 0:
            self.measured_freq=np.nan
            self.current_shift_mhz=np.nan
            self.measured_conc=np.nan
            return
        self.measured_freq=float(frequency_hz)*1e-6
        self.last_fft=time.monotonic()
        shift=self.measured_freq-self.baseline_mhz
        self.current_shift_mhz=shift
        if self.locked is True and 0<=shift<=self.cal.at(153000):
            self.measured_conc=self.cal.inverse(shift)
        else:
            self.measured_conc=np.nan
        # Real plot time axis, paired values from one received frequency sample.
        if self.response_start is None:
            self.response_start=ts
        self.response_elapsed_hist.append(ts-self.response_start)
        self.response_shift_hist.append(shift)
        self.response_conc_hist.append(self.measured_conc)

    def apply(self,pkt,received,sender=None):
        ts=self._time(received)
        self.t=ts
        self.last_any=received
        self.network_status='正在接收 UDP 数据'
        self.messages+=1
        if sender is not None: self.sender=f'{sender[0]}:{sender[1]}'
        typ=pkt.get('type')
        if typ in ('status','telemetry'):
            seq=pkt.get('seq')
            if seq is not None and seq==self.status_seq:
                return
            if seq is not None:self.status_seq=seq
            self.status_packets+=1
            self.last_status=received
            self.state=pkt.get('state',self.state)
            if 'locked' in pkt:
                self.locked=bool(pkt['locked'])
                if self.locked is False:
                    self.measured_conc=np.nan
            self.fault=pkt.get('fault',self.fault)
            if 'da_v' in pkt:
                self._switch_da_unit('V')
                self.da=pkt['da_v'];self.last_da_v=received
            elif 'dac_code' in pkt:
                self.dac_code=pkt['dac_code']
                if self.last_da_v is None or received-self.last_da_v>3.0:
                    self._switch_da_unit('code')
                    self.da=self.dac_code
            if 'pd_v' in pkt:
                self.pd=pkt['pd_v'];self.last_pd_v=received
            if 'error_mv' in pkt:
                self._switch_error_unit('mV')
                self.err=pkt['error_mv'];self.last_error_mv=received
            elif 'error_code' in pkt:
                if self.last_error_mv is None or received-self.last_error_mv>3.0:
                    self._switch_error_unit('code')
                    self.err=pkt['error_code']
            self._update_feedback()
            if self.fault:
                self.event=f'FPGA 锁定故障码 {self.fault}'
            else:
                self.event=f'收到锁定状态：{self.state}'
        if typ in ('telemetry','temperature'):
            if 'temperature_model' in pkt:
                self.temperature_source='模型温度' if pkt['temperature_model'] else '传感器温度'
            if 'temperature_fault' in pkt:
                self.temperature_fault=bool(pkt['temperature_fault'])
            if 'temperature_c' in pkt:
                self.temperature_c=pkt['temperature_c'];self.last_temperature=received
            if 'temperature_target_c' in pkt: self.temperature_target_c=pkt['temperature_target_c']
            if 'heater_duty_pct' in pkt: self.heater_duty_pct=pkt['heater_duty_pct']
        if typ in ('fft_result','telemetry'):
            if typ=='fft_result':
                seq=pkt.get('seq')
                quality=pkt.get('trusted',pkt.get('frequency_valid',True))
                if seq is not None and seq==self.fft_seq and quality==self.fft_quality:return
                self.fft_seq=seq
                self.fft_quality=quality
                self.fft_packets+=1
            if 'frequency_hz' in pkt or (typ=='fft_result' and not pkt.get('trusted',True)):
                good=pkt.get('trusted',pkt.get('frequency_valid',True))
                if not good: self.invalid_fft+=1
                self._update_frequency(pkt.get('frequency_hz'),ts,good)
                if good and np.isfinite(self.measured_freq):
                    self.event=f'收到拍频测量结果：{self.measured_freq:.5f} MHz'
                elif not good:
                    self.event='收到测频质量无效标志'
        if typ=='adc_samples':
            self.sample_rate_hz=pkt['sample_rate_hz']
            self.beat_wave=np.asarray(pkt['samples'],dtype=float)
            self.last_wave=received
            # Raw ADC waveform permits a REAL FFT calculation on PC, but this
            # is not described as the FPGA's full FFT spectrum.
            y=self.beat_wave
            n=len(y)
            w=np.hanning(n)
            y=(y-y.mean())*w
            spec=np.fft.rfft(y)
            denom=max(n*np.mean(w)*.5*8192,1e-12)
            self.fft=20*np.log10(np.maximum(np.abs(spec)/denom,1e-10))
            self.frequencies=np.fft.rfftfreq(n,d=1/self.sample_rate_hz)*1e-6
            self.last_spec=received
        if typ=='spectrum':
            db=np.asarray(pkt['dbfs'],dtype=float)
            self.fft=db
            self.frequencies=(pkt['start_hz']+np.arange(len(db))*pkt['bin_hz'])*1e-6
            self.last_spec=received
        if typ in ('status','telemetry','temperature','fft_result'):
            self._log_data(ts,typ)

    def mark_stale(self,now):
        if self.last_any is None:
            self.network_status='等待 UDP 数据'
            return
        if now-self.last_any>3:
            self.network_status='UDP 数据中断'
            self.state='通信超时'
            self.locked=None
        if self.last_status is None or now-self.last_status>3:
            self.locked=None
            self.measured_conc=np.nan
            self.da=np.nan;self.pd=np.nan;self.err=np.nan;self.err_filtered=np.nan
        if self.last_pd_v is None or now-self.last_pd_v>3:
            self.pd=np.nan
        if self.last_fft is None or now-self.last_fft>3:
            self.measured_freq=np.nan;self.current_shift_mhz=np.nan;self.measured_conc=np.nan
        if self.last_temperature is None or now-self.last_temperature>3:
            self.temperature_c=np.nan;self.temperature_target_c=np.nan;self.heater_duty_pct=np.nan
        if self.last_wave is None or now-self.last_wave>4:
            self.beat_wave=np.array([],dtype=float)
        if self.last_spec is None or now-self.last_spec>4:
            self.frequencies=np.array([],dtype=float);self.fft=np.array([],dtype=float)

    def snapshot(self):
        return (np.asarray(self.t_hist),np.asarray(self.da_hist),np.asarray(self.pd_hist),
                np.asarray(self.err_hist),np.asarray(self.c_hist),np.asarray(self.beat_hist))

    def feedback_snapshot(self):
        return (np.asarray(self.t_hist),np.asarray(self.filtered_err_hist))

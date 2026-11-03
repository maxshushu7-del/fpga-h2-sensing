"""V4 packet fixtures and local sockets; these tests do not represent board capture."""
import math,socket,struct,time,unittest
from udp_protocol import parse_packet,V4
from udp_live import LiveModel,UDPListener

def fixture(seq=1,fftseq=10,freq=5000019,valid=True,state=12,fault=0,temp_flags=4,duty=32768):
    flags=0x78 | int(valid) # FFT enabled, clocks and init ready, virtual-temperature source
    return V4.pack(b'FPGA',1,flags,state,fault,seq,freq,fftseq,-123,-2345,30012,duty,temp_flags,1234,0x54454332)

class Cal:
    def at(self,x):return 903
    def inverse(self,x):return x

class V4Tests(unittest.TestCase):
    def test_units_and_source(self):
        s,f=parse_packet(fixture())
        self.assertEqual((s['dac_code'],s['error_code']),(-2345,-123))
        self.assertNotIn('da_v',s);self.assertNotIn('pd_v',s)
        self.assertAlmostEqual(s['temperature_c'],30.012)
        self.assertEqual(s['timestamp_ms'],12340)
        self.assertEqual(s['heater_duty_pct'],50.)
        self.assertTrue(s['temperature_model']);self.assertTrue(s['locked'])
        self.assertEqual((s['seq'],f['seq']),(1,10))
        self.assertEqual(f['frequency_hz'],5000019)
    def test_no_invented_waveform(self):
        m=LiveModel(Cal());now=time.monotonic()
        for p in parse_packet(fixture()):m.apply(p,now)
        self.assertEqual(len(m.beat_wave),0);self.assertEqual(len(m.fft),0)
        self.assertTrue(math.isnan(m.pd));self.assertEqual(m.da_unit,'code')
        self.assertEqual(m.temperature_source,'模型温度')
    def test_result_sequence_and_invalidation(self):
        m=LiveModel(Cal());now=time.monotonic()
        for seq in range(1,11):
            for p in parse_packet(fixture(seq=seq)):m.apply(p,now+seq*.01)
        self.assertEqual(m.status_packets,10);self.assertEqual(m.fft_packets,1)
        for p in parse_packet(fixture(seq=11,valid=False)):m.apply(p,now+.11)
        self.assertTrue(math.isnan(m.measured_freq));self.assertEqual(m.invalid_fft,1)
        for p in parse_packet(fixture(seq=12,fftseq=11,freq=10000039)):m.apply(p,now+.12)
        self.assertEqual(m.fft_packets,3);self.assertAlmostEqual(m.measured_freq,10.000039)
        m.mark_stale(time.monotonic()+5)
        self.assertTrue(math.isnan(m.measured_freq));self.assertIsNone(m.locked)
    def test_invalid_boundaries(self):
        for p in [fixture()[:-1],fixture()+b'0',b'FPGA'+bytes(36)]:
            with self.assertRaises(ValueError):parse_packet(p)
        x=bytearray(fixture());x[4]=2
        with self.assertRaises(ValueError):parse_packet(x)
    def test_saturation_and_lock_fault(self):
        s,_=parse_packet(fixture(duty=65535,fault=2,temp_flags=5))
        self.assertEqual(s['heater_duty_pct'],100.);self.assertFalse(s['locked'])
        self.assertTrue(s['temperature_fault'])
        s,_=parse_packet(fixture(state=2))
        self.assertFalse(s['locked'])
    def test_actual_loopback(self):
        u=UDPListener();self.assertTrue(u.start('127.0.0.1',0))
        sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        try:
            sock.sendto(fixture(),u.endpoint)
            end=time.monotonic()+2
            while time.monotonic()<end and u.decoded<2:time.sleep(.01)
            msgs=[e for e in u.drain() if e[0]=='packet']
            self.assertEqual(len(msgs),2)
            self.assertEqual([e[1]['type'] for e in msgs],['telemetry','fft_result'])
            self.assertEqual(u.rejected,0)
            self.assertEqual(u.datagrams,1)
        finally:sock.close();u.stop()
    def test_calibration_matches_report_interpolation(self):
        from main import Calibration
        c=Calibration()
        self.assertAlmostEqual(c.inverse(.03),.001)
        self.assertAlmostEqual(c.inverse(18),15.)
        self.assertAlmostEqual(c.at(15),18.)
        self.assertIsNone(c.inverse(.01))

if __name__=='__main__':unittest.main(verbosity=2)

"""Native UDP parser and socket integration tests (fixture data only)."""
import json
import socket
import struct
import time
import unittest
from pathlib import Path

from udp_protocol import HEADER, parse_packet
from test_udp_sender import telemetry, raw_telemetry, adc_packets
from udp_live import LiveModel, UDPListener

class NativeUDPTests(unittest.TestCase):
    def test_native_calibrated_packet(self):
        msg=telemetry(11)
        rec=parse_packet(msg)[0]
        self.assertEqual(rec['seq'],11)
        self.assertEqual(rec['state'],'已锁定')
        self.assertAlmostEqual(rec['da_v'],.6)
        self.assertAlmostEqual(rec['pd_v'],1.208)
        self.assertAlmostEqual(rec['error_mv'],1.2)
        self.assertEqual(rec['frequency_hz'],33000000)
        self.assertAlmostEqual(rec['heater_duty_pct'],6.2)
        with self.assertRaises(ValueError): parse_packet(msg[:-1])
        with self.assertRaises(ValueError): parse_packet(b'\xa5\x5a\x01'+bytes(13))

    def test_native_raw_code(self):
        rec=parse_packet(raw_telemetry(2))[0]
        self.assertEqual(rec['dac_code'],8500)
        self.assertEqual(rec['error_code'],-12)
        self.assertNotIn('da_v',rec)

    def test_adc_chunk(self):
        parts=adc_packets(7)
        self.assertEqual(len(parts),8)
        rec=parse_packet(parts[0])[0]
        self.assertEqual(rec['total_samples'],4096)
        self.assertEqual(len(rec['samples']),512)
        with self.assertRaises(ValueError):parse_packet(parts[0]+b'junk')

    def test_json_optional(self):
        x={'type':'telemetry','state':'已锁定','locked':True,'frequency_hz':33000000,
           'frequency_valid':True,'temperature_c':30.}
        rec=parse_packet(json.dumps(x).encode('utf-8'))[0]
        self.assertEqual(rec['type'],'telemetry')

    def test_udp_loopback_and_reassemble_out_of_order(self):
        import sys
        from main import Calibration
        m=LiveModel(Calibration())
        u=UDPListener()
        self.assertTrue(u.start('127.0.0.1',0))
        sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        dest=u.endpoint
        sock.sendto(telemetry(1),dest)
        chunks=adc_packets(10)
        for msg in reversed(chunks):sock.sendto(msg,dest)
        deadline=time.monotonic()+3
        while time.monotonic()<deadline and u.decoded<9:
            time.sleep(.01)
        packets=[msg for msg in u.drain() if msg[0]=='packet']
        self.assertEqual(len(packets),2)
        for _,pkt,ts,sender in packets:m.apply(pkt,ts,sender)
        self.assertAlmostEqual(m.measured_freq,33.,places=6)
        self.assertAlmostEqual(m.current_shift_mhz,32.,places=6)
        self.assertAlmostEqual(m.measured_conc,100.,places=6)
        self.assertAlmostEqual(m.temperature_c,30.012)
        self.assertEqual(len(m.beat_wave),4096)
        self.assertEqual(len(m.fft),2049)
        m.mark_stale(time.monotonic()+5)
        self.assertFalse(bool(m.locked))
        self.assertTrue(m.measured_freq!=m.measured_freq)
        self.assertTrue(m.measured_conc!=m.measured_conc)
        sock.close();u.stop()

if __name__=='__main__':unittest.main(verbosity=2)

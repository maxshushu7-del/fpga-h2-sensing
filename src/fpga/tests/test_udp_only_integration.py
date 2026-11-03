#!/usr/bin/env python3
"""V4 preflight: actual active module tree has UDP, no UART, unchanged DAC phase."""
from pathlib import Path
import re,sys
r=Path(__file__).resolve().parents[1]
top=(r/'rtl/servo/laser_lock_hw_udp_only_top.v').read_text()
core=(r/'rtl/servo/laser_lock_hw_top.v').read_text()
eth=(r/'rtl/network/udp_telemetry_bridge.v').read_text()
phy=(r/'rtl/network/rgmii_udp_tx.v').read_text()
strip=lambda s:re.sub(r'//[^\n]*','',s)
for name,s in [('top',top),('core',core)]:
    assert 'uart' not in strip(s).lower(),f'{name}: UART remains in active RTL'
for name in ['phy_tx_clk','phy_reset_n','phy_tx_ctl','phy_txd']:
    assert re.search(r'\b'+name+r'\b',top),f'RGMII output missing {name}'
assert 'udp_telemetry_bridge' in top and 'rgmii_udp_tx' in top
assert 'laser_lock_hw_top' in top
assert 'DCI_DELAY_PS(875.0)' in core
assert 'output wire [7:0] tx_byte' in eth
assert 'ODDRE1' in phy and 'BUFGCE_DIV' in phy
assert not (r/'constraints/uart_tx_pin.xdc').exists()
xc=(r/'scripts/create_project.tcl').read_text()
assert 'set_property top laser_lock_hw_udp_only_top' in xc
assert 'axau15_eth_udp_tx.xdc' in xc
assert 'uart_tx_pin.xdc' not in xc
assert 'set PROJECT_NAME contest_all' in xc
print('PASS: V4 UDP-only integration; RGMII physical pins, no UART; DAC DCI 875ps')

from pathlib import Path
import sys,json,hashlib,re,subprocess
R=Path(__file__).resolve().parents[1]
rtl=list((R/'rtl').rglob('*.v'))+list((R/'rtl').rglob('*.sv'))
assert len(rtl)>35, f'RTL count {len(rtl)}'
for f in rtl:
    t=f.read_text(encoding='utf-8-sig')
    t=re.sub(r'/\*.*?\*/','',t,flags=re.S)
    t=re.sub(r'//[^\n]*','',t)
    t=re.sub(r'"(?:\\.|[^"\\])*"','""',t)
    if len(re.findall(r'\bmodule\b',t))!=len(re.findall(r'\bendmodule\b',t)): raise ValueError(f'module mismatch {f}')
    for o,c in [('(',')'),('[',']'),('{','}')]:
        d=0
        for ch in t:
            d+=int(ch==o)-int(ch==c)
            if d<0:raise ValueError(f'bracket early {f}:{o}{c}')
        if d:raise ValueError(f'bracket mismatch {f}:{o}{c}:{d}')
for name in ['fft_core','laser_lock_hw_vio','laser_lock_ila']:
    p=R/'ip_templates'/name/(name+'.xci')
    obj=json.loads(p.read_text())
    assert obj['ip_inst']['xci_name']==name
    assert 'contest_all.gen' in obj['ip_inst']['gen_directory']
assert 'DCI_DELAY_PS(875.0)' in (R/'rtl/servo/laser_lock_hw_top.v').read_text()
assert 'module laser_lock_hw_udp_only_top' in (R/'rtl/servo/laser_lock_hw_udp_only_top.v').read_text()
# Active FPGA RTL must be UART-free; comments are ignored.
for f in rtl:
    clean = re.sub(r'//[^\n]*','',re.sub(r'/\*.*?\*/','',f.read_text(),flags=re.S))
    assert 'uart' not in clean.lower(),f'Unexpected UART dependency in FPGA RTL: {f}'
assert not (R/'constraints/uart_tx_pin.xdc').exists()
assert 'uart_tx' not in (R/'rtl/servo/laser_lock_hw_udp_only_top.v').read_text().split('module ',1)[1].split(');',1)[0]
assert '.uart_tx(' not in (R/'rtl/servo/laser_lock_hw_udp_only_top.v').read_text()
assert 'udp_telemetry_bridge' in (R/'rtl/servo/laser_lock_hw_udp_only_top.v').read_text()
assert 'rgmii_udp_tx' in (R/'rtl/servo/laser_lock_hw_udp_only_top.v').read_text()
assert 'contest_all.gen' in (R/'ip_templates/fft_core/fft_core.xci').read_text()

print(f'PASS: {len(rtl)} RTL files; UDP-only physical top; legal MMCM phase 875ps DAC; 3 standalone Vivado 2024.1 XCI IPs')
subprocess.run([sys.executable,str(R/'scripts/check_phase.py')],check=True)
subprocess.run([sys.executable,str(R/'tests/test_structural.py')],check=True)
subprocess.run([sys.executable,str(R/'tests/test_protocol.py')],check=True)
subprocess.run([sys.executable,str(R/'tests/test_udp_only_integration.py')],check=True)
subprocess.run([sys.executable,str(R/'tests/test_udp_full_frame.py')],check=True)

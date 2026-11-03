#!/usr/bin/env python3
"""Static FPGA phase-resolution check (NOT a substitute for routed STA)."""
from pathlib import Path
import re
s=(Path(__file__).resolve().parents[1]/"rtl/servo/laser_lock_hw_top.v").read_text(encoding="utf-8")
m=re.search(r"DCI_DELAY_PS\((\d+(?:\.\d+)?)\)",s)
assert m, "Hardware top missing DAC DCI phase"
phase_ps=float(m.group(1))
period_ps=4000.0
phase_deg=360.0*phase_ps/period_ps
step_deg=45.0/4.0
quant=phase_deg/step_deg
assert abs(quant-round(quant)) < 1e-9, f"DRC AVAL-168 predicted: invalid phase {phase_deg} degrees"
assert phase_ps==875.0, "Wrong V4 DAC phase"
assert abs(phase_deg-78.75) < 1e-9
print(f"V4 PHASE VALID: {phase_ps:g} ps, {phase_deg:g} degrees, {quant:g} x {step_deg:g} degree steps")

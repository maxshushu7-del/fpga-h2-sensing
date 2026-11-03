#!/usr/bin/env python3
"""Audit timing summary; never equate a generated .bit with timing closure.

Requires genuine Vivado routed report_timing_summary file.
"""
from pathlib import Path
import re,sys
root=Path(__file__).resolve().parents[1]
p=Path(sys.argv[1]) if len(sys.argv)>1 else root/"results/final_timing_summary.txt"
if not p.exists(): raise SystemExit(f"MISSING REPORT: {p}")
s=p.read_text(encoding="utf-8",errors="replace")
start=s.find("| Design Timing Summary")
if start<0: raise SystemExit("INVALID REPORT: Design Timing Summary header missing")
part=s[start:start+2000]
num=r"[-+]?\d+(?:\.\d+)?"
rx=re.compile(r"^\s*("+num+r")\s+("+num+r")\s+(\d+)\s+(\d+)\s+("+num+r")\s+("+num+r")\s+(\d+)\s+(\d+)\s+("+num+r")\s+("+num+r")",re.M)
m=rx.search(part)
if not m: raise SystemExit("INVALID REPORT: cannot parse Vivado timing summary numerical row")
wns,tns,fail_s,tot_s,whs,ths,fail_h,tot_h,wpws,tpws=m.groups()
wns,tns,whs,ths,wpws,tpws=map(float,(wns,tns,whs,ths,wpws,tpws))
fail_s,fail_h=int(fail_s),int(fail_h)
print(f"V4 TIMING: WNS={wns:+.3f} TNS={tns:+.3f} Setup fails={fail_s}; WHS={whs:+.3f} THS={ths:+.3f} Hold fails={fail_h}; WPWS={wpws:+.3f} TPWS={tpws:+.3f}")
closed=wns>=0 and tns>=0 and whs>=0 and ths>=0 and fail_s==0 and fail_h==0 and wpws>=0 and tpws>=0
print("CONSTRAINED TIMING:","PASS" if closed else "FAIL")
if "no_output_delay (10)" in s or re.search(r"There are [1-9]\d* ports with no output delay",s):
    print("NOTE: Physical I/O signoff incomplete: report has unconstrained output-delay ports (RGMII PHY timing not validated).")
if "Asynchronous driver check" in s:
    print("NOTE: Methodology CDC/reset warnings remain; timing PASS does not certify board behavior.")
if not closed: sys.exit(2)

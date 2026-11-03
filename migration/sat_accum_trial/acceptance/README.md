# Frozen sat_accum_stream acceptance

This acceptance was independently written before seeing or running candidate RTL. No candidate implementation is included. The only DUT name is `sat_accum_stream`; the candidate must be one standalone Verilog/SystemVerilog source file without external IP or include dependencies. Ports are clk, rst, signed s_x[15:0], signed s_k[7:0], s_valid, s_ready, signed m_y[15:0], m_valid, m_ready.

The synchronous active-high reset clears accumulator, output data and output valid, and cancels pending output. The arithmetic oracle uses signed integer multiplication, absolute magnitude, integer division `(magnitude+64)/128`, explicit sign restoration and comparisons for immediate signed 16-bit saturation. The oracle does not use candidate bit operations. It compares ready, valid and data before and after every tested rising edge, including data when invalid. The first initial pre-reset comparison is skipped because synchronous state is initially unspecified. No new input means the accumulator and output data hold; output consumption without replacement clears valid.

Fixed classes:
1. Signed zero and extrema: all 9 selected x values crossed with 7 selected k values; each isolated by reset and drain, plus zero increments with an existing sum.
2. Both sides and exact ties: positive and negative products at 63/64/65 offsets around multiples of 128, with both operand signs, quotient bases 0..8,254,255, and k=+/-3 cases.
3. Positive/negative saturation, repeated saturation and small opposite increments showing immediate recovery, followed by repeated large direction changes.
4. 384 consecutive valid/ready inputs, simultaneous old-result consumption and replacement, drain, and idle data holding.
5. A 128-cycle stall with changing valid input data, an 80-cycle stall with valid input low, and 1,024 deterministic mixed-valid/mixed-ready cycles.
6. Pending-output cancellation by reset with both ready states, ignored reset-time inputs, and restart from zero, repeated four times.

PRNG: local unsigned 32-bit LCG `state = state*1664525+1013904223`, initial seed 20261102. The fixed schedule contains 2,404 checked rising edges and 14,421 signal comparisons on a complete run. These are planned counts; actual counts are emitted by the simulation, not assumed from its exit code.

Run only after the independent acceptance is frozen and candidate RTL is supplied:

```powershell
& 'E:\Codex\FPGA\workspace\report_targeted_revision_20261102\ai_trial\acceptance\run_candidate.ps1' `
  -CandidateRtl 'E:\path\candidate.sv' `
  -OutputDirectory 'E:\path\empty_candidate_result'
```

Default tools: E:\Xilinx\Vivado\2024.1\bin. Override with `-VivadoBin` when necessary. Each tool has a 180-second host timeout; override with `-TimeoutSeconds`. All generated sources, logs, simulation products and task temp files stay under the selected E-drive output directory. The runner preserves a source copy and its SHA256, verifies acceptance file hashes, and requires an empty output directory. No board or cable tools are invoked.

Pass requires successful compile/elaboration/simulation, the exact PASS completion marker, a consistent JSON report, the full six passing category records, correct cycle/check accounting, and minimum observed stall/simultaneous/reset-cancellation coverage. `runner_result.json` records stage exit codes and timeouts; `tb_result.json` records actual cycles/checks, class results, coverage and the first counterexample. Failure stops at the first mismatch; subsequent classes are NOT_RUN. Missing completion is failure even if a simulator exits with code zero. Read all result statuses; never infer acceptance from a process exit alone.

Freeze files are listed in frozen_manifest.json. The SHA256 of that manifest is reported separately to the parent task. Syntax-only validation of the testbench is permitted before candidates arrive; full DUT simulation is deferred until the parent supplies candidates.


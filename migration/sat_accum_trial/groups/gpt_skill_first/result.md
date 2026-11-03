# sat_accum_stream — self-test result

Status: PASS. Candidate implementation and self-test only; no other candidate or fixed acceptance tests were inspected.

The frozen numeric/cycle specification is in contract.md. The independent Python reference uses unlimited integer multiplication, divmod(abs(p),128), a nearest-integer decision, and per-transaction integer clamping. It does not reproduce RTL slicing/sign-extension/shift expressions. The reference was checked against 11 hand cases, 4864 independent Fraction nearest-distance cases, the full 65536-value identity round(x*(-128)/128)=-x, and 65536 increment-range observability-margin checks.

Actual Vivado 2024.1 run: xvlog analysis PASS; xelab elaboration PASS; xsim completion marker PASS; independently parsed observed-cycle CSV PASS. Two complete runs through scripts/run.ps1, including the final test-margin enhancement, also ended REGRESSION_PASS. The full original suite was retained after the startup-path correction.

Coverage (exact observations and zero mismatches):

| Event / set | Count |
|---|---:|
| Checked clock cycles | 664555 |
| Accepted inputs | 431807 |
| Consumed outputs | 230255 |
| Simultaneous consumption/replacement | 224755 |
| Held/backpressured valid cycles | 24238 |
| Reset edges | 201566 |
| Pending results cancelled by reset | 201552 |
| Positive / negative exact half increments | 1052 / 1074 |
| Positive / negative saturation events | 2818 / 2662 |
| Boundary input x values against every coefficient | 19 x 256 cases |
| Exhaustive signed 16-bit x against k=-128,-1,127 | 196608 cases |
| Seeded random protocol cycles | 60000 |

Seed: 0x51A7C0DE (1369948382). Exhaustive numeric cases start with the opposite-sign two-unit state, exposing every increment including +32768 with room for both neighboring one-unit errors. Generation-time expectations and post-run observation checking use one mathematical Oracle at two comparison locations; they are not two independent reference models. Tests inspect pre-edge registered outputs (including synchronous reset), combinational ready, post-edge valid/y, post-edge ready, source bubbles, consumer stalls, same-edge I/O, reset cancellation and final drain. Exact integer tolerance is zero. Aggregate counts include deliberately frequent resets for isolated arithmetic tests; they are not distinct reset algorithms.

No DUT functional mismatch or RTL fix occurred. The first xsim invocation did not start simulation because the absolute Windows-backslash Tcl path was interpreted for escapes; logs/attempt_01_xsim_tcl_path*.log preserve that failure. The one-argument runner repair, pre-simulation audit improvements, and final arithmetic-test margin enhancement are documented in review_and_corrections.md. Missing PASS markers fail the runner even if xsim exits zero.

Review provenance: a collaborating child agent reviewed RTL, contract and testbench. It was not an independent model tool; no model ID or multi-model claim is made. Numeric/ready/reset review points carry source locations or explicit counterexamples in review_and_corrections.md.

Files:
- rtl/sat_accum_stream.sv: candidate RTL, no IP.
- tb/tb_sat_accum_stream.sv: actual cycle-level simulation checker.
- scripts/reference.py: independent oracle, generation and observation comparison.
- scripts/run.ps1: complete reproducible run; run with PowerShell from an E: working directory. All generated files stay under this E: candidate root.
- data/vectors.txt and data/observed.csv: full input/expected rows and actual observed cycles.
- data/generation_summary.json and data/check_summary.json: machine-readable coverage/completion.
- logs/: original tool logs, including preserved first startup failure.
- first_acceptable/: first passing source/test/reference snapshot and original logs; SHA256 manifest inside. Its original vectors and actual observed CSV are retained under first_acceptable/data/. The current data/ holds the final stronger-margin full regression. artifact_sha256.json records the final raw evidence, while first_acceptable/raw_data_sha256.json records the first passing raw data.
- timeline.json: recorded UTC times and permission wait note. Permission request was visibly pending for at least 31 seconds; its exact total wait was not instrumented and is not invented or subtracted from elapsed time.

Not performed: synthesis, implementation, static timing, CDC analysis or board testing. This result establishes only the executed RTL functional checks and their stated coverage, not exhaustive all-x/all-k/all-protocol formal proof.


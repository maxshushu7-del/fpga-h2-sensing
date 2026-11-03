# Candidate simulation checks

Preparation started 2026-11-02T13:31:22Z. Four comparison runs executed from 2026-11-02T13:33:34.8725941Z through 2026-11-02T13:33:57.7420987Z, with Vivado Simulator 2024.1. The test author did not alter candidate RTL, inputs, or the production project.

Replay `candidate/commands.ps1` from an E-drive working directory. It compiles original input RTL and isolated candidate RTL into separate `candidate/logs/<case>` directories. `candidate/logs/run_summary.log` records each actual invocation, UTC, pass status, and RTL SHA-256; `console.log` retains the combined tool output. Each case also contains compile.log, elaborate.log and run.log.

| Test | Original input RTL | Candidate RTL |
| --- | --- | --- |
| Falling monotonic response, minimum at +1024 | Known counterexample captured: state=6, min_code=1024, servo_enable=1 | Correctly rejected: state=7, reason=1, servo_enable=0 |
| Rising monotonic response, minimum at -1024 | Rejected: state=7, reason=1, servo_enable=0 | Rejected: state=7, reason=1, servo_enable=0 |
| Final point establishes new maximum: prior max=1000, interior min=990, final max=1090 | Known counterexample captured: state=7, reason=1, half=0, despite full contrast=100 | state=3 FIND_WAIT, reason=0, min=990, max=1090, half=1040 |
| Acquisition, loss/reacquisition and flat-response rejection | All four phases pass | All four phases pass with identical selected_code=0, min_code=2, setpoint=1650, contrast=630 |

All tests retain production SPAN=1024 and STEP=2. The endpoint test matches the earlier diagnostic with only SETTLE_CLOCKS=0 and AVG_LOG2=0 changed, sampling identical point values without physical settling. The acquisition regression retains every other production parameter including AVG_LOG2=2, MIN_CONTRAST=24, LOSS_TOL=192, STABLE_SAMPLES=64 and LOST_SAMPLES=256; only SETTLE_CLOCKS=2 and RETRY_CLOCKS=10 are shortened. It adapts the existing FSM test's digital response `2000 - 6300/(9+(dac_code-3)^2)`, ADC/servo samples every three clocks and a 500-code error for loss detection. Test timeouts were expanded to cover all production scan points.

The endpoint test compiles with LEGACY_RTL only for original input RTL and explicitly requires the original incorrect behaviors, so a PASS in the legacy log documents a successful counterexample, not correct operation. No DUT force/deposit is used. The final-new-max test stops at FIND_WAIT, testing complete-sweep acceptance and half-level generation; it does not claim that this synthetic response can subsequently lock.

These are accelerated digital unit tests, not a physical optical loop or board validation. dac_at_goal is held high; DAC slew, ADC hardware, and clock-domain crossings are outside this test.

Original RTL SHA-256: EB9552DC8261F6A7734CEDE5E5DE0EB47EC5A96DCDDD50DB151824CDD25CC333.

Candidate RTL SHA-256: 1F38FFE3037864DB72059DEC983717F2B6487BABB30B4CEF2344CB5A7F516BF8.

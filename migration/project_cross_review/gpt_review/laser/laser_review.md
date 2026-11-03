# Laser review evidence

UTC start: 2026-11-02T13:14:11Z. UTC end: 2026-11-02T13:24:03Z.

Inputs read: project contract; auto_lock_fsm, pi2d_controller, servo_scheduler, laser_lock_top and directly connected ADC/filter/normalizer/calibration/actuator/DAC/parameter/clock and integration wrappers. No input or production RTL changed. All execution used the exact input files.

## L1 — P2: final sweep sample bypasses positive-edge minimum rejection

Location: inputs/rtl/laser/auto_lock_fsm.v:109 (related lines 103–113).

Trigger: the final sample at scan_code == +SPAN establishes a new minimum, while the preceding minimum is inside the scan range. The code schedules scan_min and min_code updates with nonblocking assignments at lines 103–105, then evaluates contrast/min_code at line 109 using their previous values. The positive-edge minimum therefore passes the intended edge rejection. The same branch computes half_level using extrema that omit the final sample.

Reproduction: tb_auto_lock_endpoint.v uses the real production defaults SPAN=1024, STEP=2 and MIN_CONTRAST=24, with SETTLE_CLOCKS=0 and AVG_LOG2=0 only to accelerate this unit test. After 5 reset clock cycles, assert arm, hold dac_at_goal=1 and adc_valid=arm, and on each falling edge drive adc_sample = 3000 - (signed(dac_code)+1024). This produces a monotonic falling response from 3000 to 952, with no internal dip. No force/deposit or DUT modification is used. servo_valid=0, so the test checks entry to servo mode without claiming physical lock.

Expected: the complete sweep has min_code=+SPAN, so line 109 should reject it with last_reason=1 and RETRY_WAIT; servo_enable should remain 0.

Actual: endpoint_run.log records:

```
FINAL_SWEEP t=20555000 sample=952 old_scan_min=954 old_min_code=1022 old_contrast=2046
RESULT state=6 reason=0 min_code=1024 scan_min=952 scan_max=3000 selected_code=-2 setpoint=1978 servo_enable=1
REPRODUCED: monotonic decreasing response with positive-edge minimum was accepted into LOCKING; expected RETRY_WAIT reason=1.
```

Impact: an out-of-range resonance / monotonic response is accepted as a scan containing an internal dip, and PI operation begins on the selected slope. This contradicts the explicit minimum boundary check; no assumption about optical calibration is needed.

Minimal recommendation: evaluate final sweep acceptance and half_level from extrema including the current average/min_code, or add a completion state after committing the final point. Do not change production RTL in this review.

## Checks performed

- Existing tb_auto_lock_fsm.v: PASS acquisition, loss/reacquisition, flat-signal rejection (existing_fsm_run.log).
- Existing tb_auto_lock_uart.v: see uart_run.log; accelerated UART format unit test.
- Added tb_pi2d_review.v: PASS 14 numerical cases covering signed proportional output, positive/negative saturation, integral clamp, logical and physical anti-windup, unwinding, and K2 second difference. PASS clear cancellation in all 10 processing states, with no output for 15 cycles after each cancellation (pi_run.log).
- The first PI test run sampled combinational in_ready in the same delta cycle as deasserting clear; it was a testbench timing error. The checker now waits 1 ns to settle. The initial run is retained as pi_run_initial_checker_delta_issue.log; no RTL was altered.
- Static tracing of actual integration shows auto_servo_enable deassertion from ARM cancellation/timeout accompanies auto_clear, which clears transaction_busy. A standalone enable drop without clear can leave the generic top busy, but no such un-cleared production integration path was established, so it is not a reported defect.

Limits: digital simulation only; short settle/averaging in the endpoint test and accelerated existing tests; no board, physical optical loop, or analog output validation. servo_scheduler and laser_lock_top were statically reviewed, not exhaustively simulated.


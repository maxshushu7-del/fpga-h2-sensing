# Replaying the GPT review simulations

All commands use Vivado 2024.1 and run from this E: output directory. Inputs are the immutable `../inputs` snapshot; no production RTL was changed.

```powershell
& 'E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\gpt_review\fft\run_estimator_existing.ps1'
& 'E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\gpt_review\fft\run_estimator_production.ps1'
& 'E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\gpt_review\fft\run_uart_existing.ps1'
& 'E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\gpt_review\fft\run_wrapper_boundary.ps1'
```

- `fft/estimator_existing.log`: unmodified existing 16-bin TB, production 29-bit arithmetic, 18 PASS cases.
- `fft/estimator_production.log`: new deterministic 4096-bin spectrum unit TB, 5 PASS cases. This exercises the real estimator, not an FFT transform or DDC chain.
- `fft/uart_existing.log` and `fft/uart_pin_bytes.hex`: unmodified existing TB with only its supported output-path plusarg set; 5 independently decoded 64-byte packets.
- `fft/wrapper_boundary.log`: real fft_stream_improved wrapper driven against a deliberately non-DSP handshake stub. 4096 accepted samples, 1171 stalls, early-TLAST detection, reset/reconfiguration. This is a protocol unit test, not a generated FFT-core verification.
- Each script retains compilation, elaboration and simulator console logs alongside the simulator log.
- `input_hash_check.json`: all 39 input snapshot files match manifest SHA-256 values; this check does not read original-project source files.

The snapshot omits the generated `fft_core` IP and coefficient files. The measurement RTL hardcodes coefficient paths to the original project. Full-chain existing measurement tests were therefore not run under the input-only rule. No original project paths were read or written to supply those dependencies. One initial UART invocation failed at command-line parsing because Windows split an equals-sign argument; the replay script contains the corrected quoting and the successful run logs.

Laser simulations are replayable with:

```powershell
& 'E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\gpt_review\laser\commands.ps1'
```

`laser/commands.ps1` contains the exact existing-FSM, endpoint reproduction, PI2D numerical/clear and existing-UART compile/elaborate/run commands. `laser/laser_review.md` provides the laser sub-review and its UTC interval. The successful final PI run includes 14 numerical cases and clear cancellation in all 10 processing states.

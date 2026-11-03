$ErrorActionPreference='Stop'
$bin='E:\Xilinx\Vivado\2024.1\bin'
$src='E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\inputs'
Set-Location -LiteralPath 'E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\gpt_review\fft'
& "$bin\xvlog.bat" --sv "$src\rtl\platform\uart_byte_tx.v" "$src\rtl\measurement\result_uart_v2.v" "$src\existing_tests\fft\tb_result_uart_v2.sv" 2>&1 | Tee-Object -FilePath uart_compile.log
if($LASTEXITCODE -ne 0) {throw 'xvlog failed'}
& "$bin\xelab.bat" tb_result_uart_v2 -s uart_existing -debug typical 2>&1 | Tee-Object -FilePath uart_elaborate.log
if($LASTEXITCODE -ne 0) {throw 'xelab failed'}
& "$bin\xsim.bat" uart_existing -testplusarg '"UART_HEX_PATH=E:/Codex/FPGA/workspace/report_targeted_revision_20261102/project_cross_review/gpt_review/fft/uart_pin_bytes.hex"' -runall -log uart_existing.log 2>&1 | Tee-Object -FilePath uart_console.log
if($LASTEXITCODE -ne 0) {throw 'xsim failed'}


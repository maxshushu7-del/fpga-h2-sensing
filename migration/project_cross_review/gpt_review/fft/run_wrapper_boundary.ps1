$ErrorActionPreference='Stop'
$bin='E:\Xilinx\Vivado\2024.1\bin'
$src='E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\inputs'
Set-Location -LiteralPath 'E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\gpt_review\fft'
& "$bin\xvlog.bat" --sv "$src\rtl\measurement\fft_stream_improved.v" tb_fft_wrapper_boundary.sv 2>&1 | Tee-Object -FilePath wrapper_compile.log
if($LASTEXITCODE -ne 0) {throw 'xvlog failed'}
& "$bin\xelab.bat" tb_fft_wrapper_boundary -s wrapper_boundary -debug typical 2>&1 | Tee-Object -FilePath wrapper_elaborate.log
if($LASTEXITCODE -ne 0) {throw 'xelab failed'}
& "$bin\xsim.bat" wrapper_boundary -runall -log wrapper_boundary.log 2>&1 | Tee-Object -FilePath wrapper_console.log
if($LASTEXITCODE -ne 0) {throw 'xsim failed'}

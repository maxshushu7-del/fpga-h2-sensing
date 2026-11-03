$ErrorActionPreference='Stop'
$bin='E:\Xilinx\Vivado\2024.1\bin'
$src='E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\inputs'
Set-Location -LiteralPath 'E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\gpt_review\fft'
& "$bin\xvlog.bat" --sv "$src\rtl\measurement\spectral_estimator.v" "$src\existing_tests\fft\tb_spectral_estimator.sv" 2>&1 | Tee-Object -FilePath estimator_compile.log
if($LASTEXITCODE -ne 0) {throw 'xvlog failed'}
& "$bin\xelab.bat" tb_spectral_estimator -s estimator_existing -debug typical 2>&1 | Tee-Object -FilePath estimator_elaborate.log
if($LASTEXITCODE -ne 0) {throw 'xelab failed'}
& "$bin\xsim.bat" estimator_existing -runall -log estimator_existing.log 2>&1 | Tee-Object -FilePath estimator_run_console.log
if($LASTEXITCODE -ne 0) {throw 'xsim failed'}

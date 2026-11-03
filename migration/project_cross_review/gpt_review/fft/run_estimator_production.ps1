$ErrorActionPreference='Stop'
$bin='E:\Xilinx\Vivado\2024.1\bin'
$src='E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\inputs'
Set-Location -LiteralPath 'E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\gpt_review\fft'
& "$bin\xvlog.bat" --sv "$src\rtl\measurement\spectral_estimator.v" tb_estimator_production.sv 2>&1 | Tee-Object -FilePath estimator_production_compile.log
if($LASTEXITCODE -ne 0) {throw 'xvlog failed'}
& "$bin\xelab.bat" tb_estimator_production -s estimator_production -debug typical 2>&1 | Tee-Object -FilePath estimator_production_elaborate.log
if($LASTEXITCODE -ne 0) {throw 'xelab failed'}
& "$bin\xsim.bat" estimator_production -runall -log estimator_production.log 2>&1 | Tee-Object -FilePath estimator_production_console.log
if($LASTEXITCODE -ne 0) {throw 'xsim failed'}

param([string]$VivadoBin="E:/Xilinx/Vivado/2024.1/bin")
$ErrorActionPreference="Stop"
$repoRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fpgaRoot=Join-Path $repoRoot "src/fpga"
$env:TMP=Join-Path $fpgaRoot "task_temp"
$env:TEMP=$env:TMP
New-Item -ItemType Directory -Force -Path $env:TMP | Out-Null
Push-Location $fpgaRoot
try { & (Join-Path $VivadoBin "vivado.bat") -mode batch -source scripts/create_project.tcl -log create_project.log -journal create_project.jou; if($LASTEXITCODE-ne 0){throw "Vivado project creation failed"} } finally { Pop-Location }

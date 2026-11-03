param([Parameter(Mandatory=$true)][string]$OutputRoot,[string]$VivadoBin='E:/Xilinx/Vivado/2024.1/bin')
$ErrorActionPreference='Stop'
$base=Split-Path -Parent $PSScriptRoot
$tools=$VivadoBin
if(Test-Path -LiteralPath $OutputRoot){throw 'Choose a new output directory to preserve archived logs.'}
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$root=Join-Path $base 'candidate'
$legacy=Join-Path $base 'inputs/rtl/laser/auto_lock_fsm.v'
$candidate=Join-Path $root 'rtl/auto_lock_fsm.v'
$summary=Join-Path $OutputRoot 'run_summary.log'
"UTC start $((Get-Date).ToUniversalTime().ToString('o'))" | Set-Content -LiteralPath $summary
function Invoke-Case([string]$name,[string]$rtl,[string]$test,[string]$top,[bool]$old){
 $out=Join-Path $OutputRoot $name
 New-Item -ItemType Directory -Path $out -Force | Out-Null
 Push-Location -LiteralPath $out
 try {
  $args=@($rtl,(Join-Path $root ('tests/'+$test)))
  if($old){$args=@('-d','LEGACY_RTL')+$args}
  "UTC $((Get-Date).ToUniversalTime().ToString('o')) NAME=$name RTL_SHA256=$((Get-FileHash -LiteralPath $rtl -Algorithm SHA256).Hash)" | Add-Content -LiteralPath $summary
  "xvlog $($args -join ' ')" | Add-Content -LiteralPath $summary
  & ($tools+'/xvlog.bat') @args *>&1 | Tee-Object -FilePath 'compile.log'
  if($LASTEXITCODE -ne 0){throw "compile failed $name"}
  "xelab $top -s sim" | Add-Content -LiteralPath $summary
  & ($tools+'/xelab.bat') $top '-s' 'sim' *>&1 | Tee-Object -FilePath 'elaborate.log'
  if($LASTEXITCODE -ne 0){throw "elaborate failed $name"}
  'xsim sim -runall' | Add-Content -LiteralPath $summary
  & ($tools+'/xsim.bat') 'sim' '-runall' *>&1 | Tee-Object -FilePath 'run.log'
  $output=Get-Content -LiteralPath 'run.log' -Raw
  if($LASTEXITCODE -ne 0 -or $output -match 'Fatal:|ERROR:|\$fatal' -or $output -notmatch 'PASS (ENDPOINT_SUITE|PRODUCTION_SPAN_REGRESSION)'){throw "simulation failed $name"}
  "PASS $name" | Add-Content -LiteralPath $summary
 } finally {Pop-Location}
}
Invoke-Case 'legacy_endpoints' $legacy 'tb_auto_lock_candidate_endpoints.v' 'tb_auto_lock_candidate_endpoints' $true
Invoke-Case 'candidate_endpoints' $candidate 'tb_auto_lock_candidate_endpoints.v' 'tb_auto_lock_candidate_endpoints' $false
Invoke-Case 'legacy_production_span' $legacy 'tb_auto_lock_production_span.v' 'tb_auto_lock_production_span' $false
Invoke-Case 'candidate_production_span' $candidate 'tb_auto_lock_production_span.v' 'tb_auto_lock_production_span' $false
"UTC end $((Get-Date).ToUniversalTime().ToString('o'))" | Add-Content -LiteralPath $summary

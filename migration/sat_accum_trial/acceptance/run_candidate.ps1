[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$CandidateRtl,
  [Parameter(Mandatory=$true)][string]$OutputDirectory,
  [string]$VivadoBin = 'E:\Xilinx\Vivado\2024.1\bin',
  [ValidateRange(10,1800)][int]$TimeoutSeconds = 180
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$candidate = (Resolve-Path -LiteralPath $CandidateRtl).Path
$out = [IO.Path]::GetFullPath($OutputDirectory)
if ($out -notmatch '^[Ee]:\\') { throw 'All new results must be stored on E:.' }
if ($out.TrimEnd('\') -eq $root.TrimEnd('\')) { throw 'Use a separate empty output directory.' }
if (Test-Path -LiteralPath $out) {
  if (@(Get-ChildItem -LiteralPath $out -Force).Count -ne 0) { throw 'Output directory must be empty; existing evidence is preserved.' }
} else { [void](New-Item -ItemType Directory -Path $out) }
foreach ($tool in @('xvlog.bat','xelab.bat','xsim.bat')) {
  if (-not (Test-Path -LiteralPath (Join-Path $VivadoBin $tool) -PathType Leaf)) { throw "Vivado tool not found: $tool in $VivadoBin" }
}
$manifestPath = Join-Path $root 'frozen_manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
foreach ($entry in $manifest.files) {
  $actual = (Get-FileHash -LiteralPath (Join-Path $root $entry.path) -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $entry.sha256) { throw "Frozen acceptance file changed: $($entry.path)" }
}
$script:stages = @()
$result = [ordered]@{
  schema=1; status='FAIL'; seed=20261102; start_utc=[DateTime]::UtcNow.ToString('o');
  candidate_path=$candidate; candidate_sha256=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant();
  manifest_sha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant();
  output_directory=$out; completion_marker_found=$false; testbench=$null; error=$null; stages=@()
}
function Invoke-VivadoTool([string]$ToolName, [string[]]$ToolArguments, [string]$StageName) {
  $parts = @((Join-Path $VivadoBin $ToolName)) + $ToolArguments
  foreach ($part in $parts) { if ($part -match '[\r\n"%]') { throw 'Unsupported command character in tool argument.' } }
  $command = ($parts | ForEach-Object { '"' + $_ + '"' }) -join ' '
  $cmdFile = Join-Path $out ($StageName + '.cmd')
  $stdout = Join-Path $out ($StageName + '.stdout.log')
  $stderr = Join-Path $out ($StageName + '.stderr.log')
  "@echo off`r`ncall $command`r`nexit /b %errorlevel%`r`n" | Set-Content -LiteralPath $cmdFile -Encoding ascii
  $timer = [Diagnostics.Stopwatch]::StartNew()
  $process = Start-Process -FilePath $env:ComSpec -ArgumentList ('/d /v:off /s /c ""{0}""' -f $cmdFile) -WorkingDirectory $out -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
  $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
  if ($timedOut) {
    & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F | Out-File -LiteralPath (Join-Path $out ($StageName + '.timeout.log'))
    [void]$process.WaitForExit(10000)
  } else { $process.WaitForExit() }
  $timer.Stop(); $process.Refresh()
  $exitCode = if ($timedOut) { -1 } else { $process.ExitCode }
  $script:stages += [ordered]@{name=$StageName; exit_code=$exitCode; timed_out=$timedOut; seconds=[Math]::Round($timer.Elapsed.TotalSeconds,3); stdout=$stdout; stderr=$stderr}
  if ($timedOut) { throw "$StageName exceeded $TimeoutSeconds seconds." }
  return $exitCode
}
$oldTemp = $env:TEMP; $oldTmp = $env:TMP; $oldLocalData = $env:XILINX_LOCAL_USER_DATA
Push-Location -LiteralPath $out
try {
  $taskTemp = Join-Path $out 'tmp'
  [void](New-Item -ItemType Directory -Path $taskTemp)
  $env:TEMP=$taskTemp; $env:TMP=$taskTemp; $env:XILINX_LOCAL_USER_DATA='no'
  # Evaluate a preserved E-drive copy so the evidence identifies the exact source.
  $sourceCopy = Join-Path $out 'candidate.sv'
  Copy-Item -LiteralPath $candidate -Destination $sourceCopy
  if ((Get-FileHash -LiteralPath $sourceCopy -Algorithm SHA256).Hash.ToLowerInvariant() -ne $result.candidate_sha256) { throw 'Candidate changed while it was copied.' }
  $tb = Join-Path $root 'tb_sat_accum_stream.sv'
  if ((Invoke-VivadoTool 'xvlog.bat' @('-sv',$sourceCopy,$tb) '01_compile') -ne 0) { throw 'RTL or testbench compilation failed; inspect 01_compile logs.' }
  if ((Invoke-VivadoTool 'xelab.bat' @('work.tb_sat_accum_stream','-s','acceptance_snapshot','--timescale','1ns/1ps') '02_elaborate') -ne 0) { throw 'Elaboration failed; inspect 02_elaborate logs.' }
  $simulationExit = Invoke-VivadoTool 'xsim.bat' @('acceptance_snapshot','-runall','-onfinish','quit') '03_simulate'
  $log = Get-Content -LiteralPath (Join-Path $out '03_simulate.stdout.log') -Raw
  $marker = [regex]::Match($log,'(?m)^SAT_ACCUM_ACCEPTANCE_COMPLETE status=PASS seed=20261102 cycles=(\d+) checks=(\d+)\r?$')
  $result.completion_marker_found=$marker.Success
  $reportPath = Join-Path $out 'tb_result.json'
  if (Test-Path -LiteralPath $reportPath) { $result.testbench = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json }
  if ($null -eq $result.testbench) { throw 'Testbench report is missing; an exit code alone cannot pass acceptance.' }
  $tbResult = $result.testbench
  if ($simulationExit -ne 0 -or -not $marker.Success -or $tbResult.status -ne 'PASS') { throw "Simulation did not complete a passing acceptance run. First counterexample: $($tbResult.first_counterexample)" }
  if ($tbResult.seed -ne 20261102 -or $tbResult.cycles -ne [int]$marker.Groups[1].Value -or $tbResult.signal_checks -ne [int]$marker.Groups[2].Value) { throw 'Completion marker and testbench report disagree.' }
  if ($tbResult.signal_checks -ne (6 * $tbResult.cycles - 3)) { throw 'Unexpected cycle/check accounting.' }
  if (@($tbResult.categories).Count -ne 6 -or @($tbResult.categories | Where-Object { $_.status -ne 'PASS' -or $_.signal_checks -le 0 }).Count -ne 0) { throw 'All six categories must explicitly pass.' }
  if ($null -ne $tbResult.first_counterexample -or $tbResult.max_stall_run -lt 128 -or $tbResult.simultaneous_handshakes -lt 383 -or $tbResult.reset_cancellations -lt 8) { throw 'Required coverage or counterexample checks failed.' }
  $result.status='PASS'
} catch {
  $result.error=$_.Exception.Message
} finally {
  $result.stages=$script:stages
  $result['finish_utc']=[DateTime]::UtcNow.ToString('o')
  $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $out 'runner_result.json') -Encoding utf8
  $env:TEMP=$oldTemp; $env:TMP=$oldTmp; $env:XILINX_LOCAL_USER_DATA=$oldLocalData
  Pop-Location
}
$result | ConvertTo-Json -Depth 12
if ($result.status -eq 'PASS') { exit 0 } else { exit 1 }

param(
    [Parameter(Mandatory=$true)][string]$VivadoBin,
    [Parameter(Mandatory=$true)][string]$Python,
    [switch]$Implementation
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$trialRoot = $PSScriptRoot.Replace('\','/')
$trialRun = Join-Path $trialRoot ('verification/run_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $trialRun -ErrorAction Stop | Out-Null
$trialOldTemp = $env:TEMP
$trialOldTmp = $env:TMP
$env:TEMP = $trialRun
$env:TMP = $trialRun
$trialSourceBefore = (Get-FileHash -LiteralPath "$trialRoot/rtl/fir4.sv").Hash
$trialCases = @(
    @{ Name='good'; Source="$trialRoot/rtl/fir4.sv"; Reject=$false },
    @{ Name='rounding'; Source="$trialRun/mutants/fir4_rounding.sv"; Reject=$true },
    @{ Name='sign'; Source="$trialRun/mutants/fir4_sign.sv"; Reject=$true },
    @{ Name='valid'; Source="$trialRun/mutants/fir4_valid.sv"; Reject=$true },
    @{ Name='restored'; Source="$trialRoot/rtl/fir4.sv"; Reject=$false }
)
$trialSummary = @()
try {
    & $Python -B -X utf8 "$trialRoot/scripts/test_reference.py" 2>&1 | Tee-Object -FilePath "$trialRun/reference_tests.txt"
    if($LASTEXITCODE -ne 0) { throw 'Reference self-check failed' }
    & $Python -B -X utf8 "$trialRoot/scripts/make_vectors.py" --out "$trialRun/data" | Tee-Object -FilePath "$trialRun/vector_generation.txt"
    if($LASTEXITCODE -ne 0) { throw 'Vector generation failed' }
    & $Python -B -X utf8 "$trialRoot/scripts/make_mutants.py" --source "$trialRoot/rtl/fir4.sv" --out "$trialRun/mutants"
    if($LASTEXITCODE -ne 0) { throw 'Fault variant generation failed' }
    foreach($trialCase in $trialCases) {
        $trialCaseRun = (Join-Path $trialRun $trialCase.Name).Replace('\','/')
        New-Item -ItemType Directory -Path $trialCaseRun | Out-Null
        Copy-Item -LiteralPath "$trialRun/data/stimulus.txt" -Destination "$trialCaseRun/stimulus.txt"
        Push-Location -LiteralPath $trialCaseRun
        try {
            & "$VivadoBin/xvlog.bat" --sv $trialCase.Source "$trialRoot/sim/tb_fir4.sv" 2>&1 | Tee-Object -FilePath 'compile_console.txt'
            if($LASTEXITCODE -ne 0) { throw "Compilation failed: $($trialCase.Name)" }
            & "$VivadoBin/xelab.bat" tb_fir4 -s fir_trial 2>&1 | Tee-Object -FilePath 'elaborate_console.txt'
            if($LASTEXITCODE -ne 0) { throw "Elaboration failed: $($trialCase.Name)" }
            & "$VivadoBin/xsim.bat" fir_trial -tclbatch "$trialRoot/sim/run_all.tcl" `
                -log "$trialCaseRun/simulate.log" 2>&1 | Tee-Object -FilePath 'simulate_console.txt'
            $trialSimExit = $LASTEXITCODE
            if(-not (Test-Path -LiteralPath 'status.txt')) { throw 'Simulator did not complete its checks' }
            $trialStatus = Get-Content -LiteralPath 'status.txt' -Raw | ConvertFrom-StringData
            if($trialStatus.COMPLETED -ne '1') { throw 'Incomplete simulation' }
            & $Python -B -X utf8 "$trialRoot/tools/compare_vectors.py" --expected "$trialRun/data/expected.csv" --actual "$trialCaseRun/actual.csv" --columns y | Tee-Object -FilePath 'comparison.json'
            $trialCompareExit = $LASTEXITCODE
            $trialComparison = Get-Content -LiteralPath 'comparison.json' -Raw | ConvertFrom-Json
            if($trialCase.Reject) {
                if([int]$trialStatus.ERRORS -le 0 -or $trialCompareExit -ne 1 -or $trialComparison.status -ne 'FAIL') {
                    throw "Injected fault was not correctly rejected: $($trialCase.Name)"
                }
                $trialOutcome = 'INJECTED_FAULT_REJECTED'
            } else {
                if($trialSimExit -ne 0 -or [int]$trialStatus.ERRORS -ne 0 -or $trialCompareExit -ne 0 -or $trialComparison.status -ne 'PASS') {
                    throw "Correct implementation failed: $($trialCase.Name)"
                }
                $trialOutcome = 'PASS'
            }
            $trialSummary += [pscustomobject]@{
                name=$trialCase.Name; outcome=$trialOutcome; deliberately_injected=$trialCase.Reject;
                cycles=[int]$trialStatus.CYCLES; checks=[int]$trialStatus.CHECKS;
                outputs=[int]$trialStatus.ACTUAL_OUTPUTS; errors=[int]$trialStatus.ERRORS;
                valid_errors=[int]$trialStatus.VALID_ERRORS; value_errors=[int]$trialStatus.VALUE_ERRORS;
                comparison=$trialComparison.status; simulator_exit=$trialSimExit;
                first_mismatch=(Select-String -LiteralPath 'simulate_console.txt' -Pattern '^MISMATCH' | Select-Object -First 1 -ExpandProperty Line)
            }
        } finally { Pop-Location }
    }
    if($trialSourceBefore -ne (Get-FileHash -LiteralPath "$trialRoot/rtl/fir4.sv").Hash) { throw 'Source changed during regression' }
    $trialResult = [ordered]@{
        status='PASS'; evidence='AUTHOR_EXECUTED_SIMULATION_AND_EXPLICIT_FAULT_INJECTION';
        rtl_sha256=$trialSourceBefore;
        comparator_sha256=(Get-FileHash -LiteralPath "$trialRoot/tools/compare_vectors.py").Hash;
        cases=$trialSummary; independent_user=$false; hardware_tested=$false;
        implementation_requested=[bool]$Implementation
    }
    $trialResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$trialRun/summary.json" -Encoding utf8
    if($Implementation) {
        $trialImplementation = Join-Path $trialRun 'implementation'
        New-Item -ItemType Directory -Path $trialImplementation | Out-Null
        Push-Location -LiteralPath $trialImplementation
        try {
            & "$VivadoBin/vivado.bat" -mode batch -source "$trialRoot/scripts/implement.tcl" `
                -log "$trialImplementation/implement.log" -journal "$trialImplementation/implement.jou" `
                -tclargs $trialRoot $trialImplementation 2>&1 | Tee-Object -FilePath 'implementation_console.txt'
            if($LASTEXITCODE -ne 0) { throw 'OOC implementation did not finish' }
            if(-not (Test-Path -LiteralPath 'implementation_complete.txt')) { throw 'Missing implementation completion record' }
        } finally { Pop-Location }
    }
    "FIR_SKILL_TRIAL_PASS $trialRun"
} finally {
    $env:TEMP = $trialOldTemp
    $env:TMP = $trialOldTmp
}

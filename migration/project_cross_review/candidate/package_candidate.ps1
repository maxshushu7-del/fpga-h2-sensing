$ErrorActionPreference='Stop'
$root='E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review'
Set-Location -LiteralPath $root
$diff=@(git -c core.autocrlf=false diff --no-index -- 'inputs/rtl/laser/auto_lock_fsm.v' 'candidate/rtl/auto_lock_fsm.v')
if($LASTEXITCODE -gt 1){throw 'git diff failed'}
$diff=$diff | ForEach-Object { $_.Replace('a/inputs/rtl/laser/auto_lock_fsm.v','a/rtl/laser/auto_lock_fsm.v').Replace('b/candidate/rtl/auto_lock_fsm.v','b/rtl/laser/auto_lock_fsm.v') }
$diff | Set-Content -LiteralPath "$root\candidate\auto_lock_fsm.patch"
$paths=@('inputs/rtl/laser/auto_lock_fsm.v','candidate/rtl/auto_lock_fsm.v','candidate/auto_lock_fsm.patch')
$rows=foreach($relative in $paths){[pscustomobject]@{path=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $root $relative) -Algorithm SHA256).Hash.ToLowerInvariant()}}
[pscustomobject]@{utc=[DateTime]::UtcNow.ToString('o');files=@($rows);source_snapshot_matches_manifest=($rows[0].sha256 -eq 'eb9552dc8261f6a7734cede5e5de0eb47ec5a96dcddd50db151824cdd25cc333')} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$root\candidate\source_hashes.json"

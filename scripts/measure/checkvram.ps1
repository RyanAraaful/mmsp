$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$f = "$PrimaryRoot/vram_700.csv"
$lines = Get-Content $f
Write-Host (\"count=\" + $lines.Count)
Write-Host '--- head 5 ---'
$lines | Select-Object -First 5 | Write-Host
Write-Host '--- around transition ---'
$lines | Select-Object -Last 30 | Write-Host
Write-Host '--- patch log start/end ---'
Select-String 'Processing view 1 /|Elapsed time' "$PrimaryRoot/log_patch700.txt" | Select-Object -First 3 -Last 3 | Write-Host
Write-Host '--- distinct gpu values ---'
$lines | ForEach-Object { ($_ -split ',')[0].Trim() } | Group-Object | Sort-Object Count -Descending | Select-Object -First 10 | Format-Table Count,Name -AutoSize | Out-String | Write-Host

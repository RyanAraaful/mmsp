$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$outdir = "$PrimaryRoot"
Write-Host '--- log_patch_singlepass tail ---'
if (Test-Path "$outdir/log_patch_singlepass.txt") { Get-Content "$outdir/log_patch_singlepass.txt" -Tail 6 } else { Write-Host 'MISSING log_patch_singlepass.txt' }
Write-Host '--- log_fusion_singlepass tail ---'
if (Test-Path "$outdir/log_fusion_singlepass.txt") { Get-Content "$outdir/log_fusion_singlepass.txt" -Tail 6 } else { Write-Host 'MISSING log_fusion_singlepass.txt' }
Write-Host '--- maps count ---'
$dm = (Get-ChildItem "$outdir/dense700/stereo/depth_maps/*.bin" -ErrorAction SilentlyContinue).Count
$nm = (Get-ChildItem "$outdir/dense700/stereo/normal_maps/*.bin" -ErrorAction SilentlyContinue).Count
Write-Host "depth_maps=$dm normal_maps=$nm"
Write-Host '--- colmap running? ---'
Get-Process colmap -ErrorAction SilentlyContinue | Select-Object Id, StartTime
Write-Host '--- vram tail ---'
if (Test-Path "$outdir/vram_singlepass.csv") { Get-Content "$outdir/vram_singlepass.csv" | Select-Object -Last 5 }

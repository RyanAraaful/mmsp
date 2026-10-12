$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$outdir = "$PrimaryRoot"
foreach ($L in @('tri15','tri65')) {
  Write-Host ("=== " + $L + " ===")
  $lp = "$outdir/log_patch_$L.txt"
  $lf = "$outdir/log_fusion_$L.txt"
  if (Test-Path $lp) { Get-Content $lp -Tail 3 } else { Write-Host 'no patch log yet' }
  if (Test-Path $lf) { Select-String 'Number of fused points|Elapsed time' $lf | Select-Object -Last 3 }
}
Write-Host '--- maps ---'
Write-Host ("depth=" + @(Get-ChildItem "$outdir/dense700/stereo/depth_maps/*.bin" -ErrorAction SilentlyContinue).Count + " normal=" + @(Get-ChildItem "$outdir/dense700/stereo/normal_maps/*.bin" -ErrorAction SilentlyContinue).Count)
Write-Host '--- colmap running? ---'
Get-Process colmap -ErrorAction SilentlyContinue | Select-Object Id, StartTime

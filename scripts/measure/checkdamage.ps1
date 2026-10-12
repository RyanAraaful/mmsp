$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$stereo = "$PrimaryRoot/dense700/stereo"
Write-Host ("stereo/depth=" + @(Get-ChildItem "$stereo/depth_maps/*.bin" -ErrorAction SilentlyContinue).Count + " normal=" + @(Get-ChildItem "$stereo/normal_maps/*.bin" -ErrorAction SilentlyContinue).Count)
foreach ($d in @('maps_backup_base','backup_pre_pyramid1','backup_pre_tri15','backup_pre_tri65')) {
  $p = "$stereo/$d"
  if (Test-Path $p) {
    $dd = @(Get-ChildItem "$p/depth_maps/*.bin" -ErrorAction SilentlyContinue).Count
    $nn = @(Get-ChildItem "$p/normal_maps/*.bin" -ErrorAction SilentlyContinue).Count
    $rr = @(Get-ChildItem "$p/*.bin" -ErrorAction SilentlyContinue).Count
    Write-Host ("$d depth_sub=$dd normal_sub=$nn root=$rr")
  } else { Write-Host ("$d MISSING") }
}
Write-Host '--- per-label fused sizes ---'
foreach ($f in @('fused_base','fused_singlepass','fused_pyramid1','fused_tri15','fused_tri65')) {
  $p = "$PrimaryRoot/dense700/$f.ply"
  if (Test-Path $p) { Write-Host ("$f " + (Get-Item $p).Length) } else { Write-Host ("$f MISSING") }
}

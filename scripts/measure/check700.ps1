$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$dense700 = "$PrimaryRoot/dense700/fused.ply"
$denseFull = "$PrimaryRoot/dense/fused.ply"
$omvs = "$PrimaryRoot/openmvs/scene_dense.ply"
foreach ($f in @($dense700, $denseFull, $omvs)) {
  if (Test-Path $f) { Get-Item $f | Select-Object FullName, Length, LastWriteTime | Format-List | Out-String | Write-Host }
  else { Write-Host \"MISSING $f\" }
}
Write-Host '--- log_patch700 tail ---'
Get-Content "$PrimaryRoot/log_patch700.txt" -Tail 5
Write-Host '--- log_fusion700 tail ---'
Get-Content "$PrimaryRoot/log_fusion700.txt" -Tail 5
Write-Host '--- vram700 tail ---'
if (Test-Path "$PrimaryRoot/vram_700.csv") { Get-Content "$PrimaryRoot/vram_700.csv" | Select-Object -Last 10 }
Write-Host '--- openmvs log check ---'
Get-ChildItem "$PrimaryRoot/openmvs/*.log","$PrimaryRoot/log_openmvs*.txt" -ErrorAction SilentlyContinue | Select-Object Name, Length

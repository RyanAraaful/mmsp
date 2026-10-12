$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$dense700 = "$LewolebaRoot/dense700/fused.ply"
$denseFull = "$LewolebaRoot/dense/fused.ply"
$omvs = "$LewolebaRoot/openmvs/scene_dense.ply"
foreach ($f in @($dense700, $denseFull, $omvs)) {
  if (Test-Path $f) { Get-Item $f | Select-Object FullName, Length, LastWriteTime | Format-List | Out-String | Write-Host }
  else { Write-Host \"MISSING $f\" }
}
Write-Host '--- log_patch700 tail ---'
Get-Content "$LewolebaRoot/log_patch700.txt" -Tail 5
Write-Host '--- log_fusion700 tail ---'
Get-Content "$LewolebaRoot/log_fusion700.txt" -Tail 5
Write-Host '--- vram700 tail ---'
if (Test-Path "$LewolebaRoot/vram_700.csv") { Get-Content "$LewolebaRoot/vram_700.csv" | Select-Object -Last 10 }
Write-Host '--- openmvs log check ---'
Get-ChildItem "$LewolebaRoot/openmvs/*.log","$LewolebaRoot/log_openmvs*.txt" -ErrorAction SilentlyContinue | Select-Object Name, Length

$ErrorActionPreference = 'Continue'
$dense700 = 'E:/dev/Lewoleba-15agustus/dense700/fused.ply'
$denseFull = 'E:/dev/Lewoleba-15agustus/dense/fused.ply'
$omvs = 'E:/dev/Lewoleba-15agustus/openmvs/scene_dense.ply'
foreach ($f in @($dense700, $denseFull, $omvs)) {
  if (Test-Path $f) { Get-Item $f | Select-Object FullName, Length, LastWriteTime | Format-List | Out-String | Write-Host }
  else { Write-Host \"MISSING $f\" }
}
Write-Host '--- log_patch700 tail ---'
Get-Content 'E:/dev/Lewoleba-15agustus/log_patch700.txt' -Tail 5
Write-Host '--- log_fusion700 tail ---'
Get-Content 'E:/dev/Lewoleba-15agustus/log_fusion700.txt' -Tail 5
Write-Host '--- vram700 tail ---'
if (Test-Path 'E:/dev/Lewoleba-15agustus/vram_700.csv') { Get-Content 'E:/dev/Lewoleba-15agustus/vram_700.csv' | Select-Object -Last 10 }
Write-Host '--- openmvs log check ---'
Get-ChildItem 'E:/dev/Lewoleba-15agustus/openmvs/*.log','E:/dev/Lewoleba-15agustus/log_openmvs*.txt' -ErrorAction SilentlyContinue | Select-Object Name, Length

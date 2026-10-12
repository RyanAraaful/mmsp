$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$dm = "$LewolebaRoot/dense700/stereo/depth_maps"
$files = Get-ChildItem "$dm/*.bin" | Sort-Object LastWriteTime
Write-Host ("count=" + $files.Count)
$photo = ($files | Where-Object { $_.Name -like '*photometric*' }).Count
$geo = ($files | Where-Object { $_.Name -like '*geometric*' }).Count
Write-Host ("photometric=" + $photo + " geometric=" + $geo)
if ($files.Count -gt 0) {
  Write-Host ("first=" + $files[0].Name + " " + $files[0].LastWriteTime.ToString('HH:mm:ss'))
  Write-Host ("last=" + $files[-1].Name + " " + $files[-1].LastWriteTime.ToString('HH:mm:ss'))
  Write-Host ("span_min=" + (($files[-1].LastWriteTime - $files[0].LastWriteTime).TotalMinutes))
}
Write-Host '--- fusion head (input type) ---'
Get-Content "$LewolebaRoot/log_fusion_singlepass.txt" -TotalCount 8
Write-Host '--- fusion points/time ---'
Select-String 'Number of fused points|Elapsed time' "$LewolebaRoot/log_fusion_singlepass.txt"
Write-Host '--- patch log linecount + gugur check ---'
(Get-Content "$LewolebaRoot/log_patch_singlepass.txt").Count
Select-String 'Ignoring reference image|ERROR|Failed' "$LewolebaRoot/log_patch_singlepass.txt" | Select-Object -First 5

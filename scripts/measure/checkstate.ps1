$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$stereo = "$PrimaryRoot/dense700/stereo"
Write-Host ("stereo/depth_maps=" + @(Get-ChildItem "$stereo/depth_maps/*.bin" -ErrorAction SilentlyContinue).Count)
Write-Host ("stereo/normal_maps=" + @(Get-ChildItem "$stereo/normal_maps/*.bin" -ErrorAction SilentlyContinue).Count)
Write-Host ("backup_pre_pyramid1 root=" + @(Get-ChildItem "$stereo/backup_pre_pyramid1/*.bin" -ErrorAction SilentlyContinue).Count)
Get-ChildItem "$stereo/backup_pre_pyramid1/*.bin" -ErrorAction SilentlyContinue | Select-Object -First 3 Name, Length
Write-Host '--- colmap running? ---'
Get-Process colmap -ErrorAction SilentlyContinue | Select-Object Id

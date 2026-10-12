$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$stereo = "$PrimaryRoot/dense700/stereo"
$backup = "$stereo/backup_pre_pyramid1"
# Depth/normal .bin share filenames -> separate subdirs (flat dir collides).
New-Item -ItemType Directory -Force "$backup/depth_maps" | Out-Null
New-Item -ItemType Directory -Force "$backup/normal_maps" | Out-Null
$strays = @(Get-ChildItem "$backup/*.bin" -ErrorAction SilentlyContinue)
foreach ($f in $strays) { Move-Item $f.FullName "$backup/depth_maps/" -Force }
$dd = @(Get-ChildItem "$stereo/depth_maps/*.bin" -ErrorAction SilentlyContinue)
foreach ($f in $dd) { Move-Item $f.FullName "$backup/depth_maps/" -Force }
$nm = @(Get-ChildItem "$stereo/normal_maps/*.bin" -ErrorAction SilentlyContinue)
foreach ($f in $nm) { Move-Item $f.FullName "$backup/normal_maps/" -Force }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$RepoRoot/scripts/run/run-ablate.ps1" -Label pyramid1 -ExtraArgs '--PatchMatchStereo.pyramid_levels 1'
exit $LASTEXITCODE

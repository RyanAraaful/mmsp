$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$stereo = "$PrimaryRoot/dense700/stereo"
$backup = "$stereo/backup_pre_conf02"
New-Item -ItemType Directory -Force "$backup/depth_maps" | Out-Null
New-Item -ItemType Directory -Force "$backup/normal_maps" | Out-Null
foreach ($f in @(Get-ChildItem "$stereo/depth_maps/*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$backup/depth_maps/" -Force }
foreach ($f in @(Get-ChildItem "$stereo/normal_maps/*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$backup/normal_maps/" -Force }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$RepoRoot/scripts/run/run-ablate.ps1" -Label conf02 -ExtraArgs '--PatchMatchStereo.pyramid_levels 1 --PatchMatchStereo.filter_min_confidence 0.2'
exit $LASTEXITCODE

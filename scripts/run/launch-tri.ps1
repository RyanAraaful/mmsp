$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$stereo = "$LewolebaRoot/dense700/stereo"
function Move-Maps($tag) {
  $backup = "$stereo/backup_pre_$tag"
  New-Item -ItemType Directory -Force "$backup/depth_maps" | Out-Null
  New-Item -ItemType Directory -Force "$backup/normal_maps" | Out-Null
  foreach ($f in @(Get-ChildItem "$stereo/depth_maps/*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$backup/depth_maps/" -Force }
  foreach ($f in @(Get-ChildItem "$stereo/normal_maps/*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$backup/normal_maps/" -Force }
  foreach ($f in @(Get-ChildItem "$backup/*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$backup/depth_maps/" -Force }
}
Move-Maps 'tri15'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$RepoRoot/scripts/run/run-ablate.ps1" -Label tri15 -ExtraArgs '--PatchMatchStereo.pyramid_levels 1 --PatchMatchStereo.max_triangulation_angle 15'
Move-Maps 'tri65'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$RepoRoot/scripts/run/run-ablate.ps1" -Label tri65 -ExtraArgs '--PatchMatchStereo.pyramid_levels 1 --PatchMatchStereo.max_triangulation_angle 65'
exit $LASTEXITCODE

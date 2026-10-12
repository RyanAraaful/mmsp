$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$stereo = "$MidaiRoot/dense/stereo"
$backup = "$stereo/backup_pre_midai_r3"
New-Item -ItemType Directory -Force "$backup/depth_maps" | Out-Null
New-Item -ItemType Directory -Force "$backup/normal_maps" | Out-Null
foreach ($f in @(Get-ChildItem "$stereo/depth_maps/*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$backup/depth_maps/" -Force }
foreach ($f in @(Get-ChildItem "$stereo/normal_maps/*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$backup/normal_maps/" -Force }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$RepoRoot/scripts/run/run-ablate.ps1" -Label midai_r3 -Workspace "$MidaiRoot/dense" -ExtraArgs '--PatchMatchStereo.pyramid_levels 1 --PatchMatchStereo.filter_min_confidence 0.2 --PatchMatchStereo.window_step 2 --PatchMatchStereo.num_iterations 1 --PatchMatchStereo.window_radius 3' -FusionExtraArgs '--StereoFusion.fuse_prior_weight 1.0 --StereoFusion.max_depth_error 0.1'
exit $LASTEXITCODE

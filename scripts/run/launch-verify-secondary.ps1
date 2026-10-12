$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$iter2flags = '--PatchMatchStereo.pyramid_levels 1 --PatchMatchStereo.filter_min_confidence 0.2 --PatchMatchStereo.window_step 2 --PatchMatchStereo.num_iterations 2'
$prior = '--StereoFusion.fuse_prior_weight 1.0'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$RepoRoot/scripts/run/run-ablate.ps1" -Label iter2_rerun -ExtraArgs $iter2flags -FusionExtraArgs $prior
$mstereo = "$SecondaryRoot/dense/stereo"
$mbackup = "$mstereo/backup_pre_secondary_iter2"
New-Item -ItemType Directory -Force "$mbackup/depth_maps" | Out-Null
New-Item -ItemType Directory -Force "$mbackup/normal_maps" | Out-Null
foreach ($f in @(Get-ChildItem "$mstereo/depth_maps/*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$mbackup/depth_maps/" -Force }
foreach ($f in @(Get-ChildItem "$mstereo/normal_maps/*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$mbackup/normal_maps/" -Force }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$RepoRoot/scripts/run/run-ablate.ps1" -Label secondary_iter2 -Workspace "$SecondaryRoot/dense" -ExtraArgs $iter2flags -FusionExtraArgs $prior
exit $LASTEXITCODE

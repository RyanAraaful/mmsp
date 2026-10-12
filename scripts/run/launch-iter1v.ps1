$ErrorActionPreference = 'Stop'
$iter1flags = '--PatchMatchStereo.pyramid_levels 1 --PatchMatchStereo.filter_min_confidence 0.2 --PatchMatchStereo.window_step 2 --PatchMatchStereo.num_iterations 1'
$prior = '--StereoFusion.fuse_prior_weight 1.0'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'E:/dev/Colmap-Kernel/scripts/run/run-ablate.ps1' -Label iter1_rerun -ExtraArgs $iter1flags -FusionExtraArgs $prior
$mstereo = 'E:/dev/Midai-14agustus/dense/stereo'
$mbackup = "$mstereo/backup_pre_midai_iter1"
New-Item -ItemType Directory -Force "$mbackup/depth_maps" | Out-Null
New-Item -ItemType Directory -Force "$mbackup/normal_maps" | Out-Null
foreach ($f in @(Get-ChildItem "$mstereo/depth_maps/*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$mbackup/depth_maps/" -Force }
foreach ($f in @(Get-ChildItem "$mstereo/normal_maps/*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$mbackup/normal_maps/" -Force }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'E:/dev/Colmap-Kernel/scripts/run/run-ablate.ps1' -Label midai_iter1 -Workspace 'E:/dev/Midai-14agustus/dense' -ExtraArgs $iter1flags -FusionExtraArgs $prior
exit $LASTEXITCODE

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$colmap = "$ColmapExe"
$proj = $SecondaryRoot
$dense = "$proj\dense"
& $colmap image_undistorter --image_path "$proj\images" --input_path "$proj\sparse\0" --output_path $dense --output_type COLMAP --max_image_size 700 2>&1 | Tee-Object "$proj\log_undistort700.txt"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$RepoRoot/scripts/run/run-ablate.ps1" -Label secondary_ws2 -Workspace $dense -ExtraArgs '--PatchMatchStereo.pyramid_levels 1 --PatchMatchStereo.filter_min_confidence 0.2 --PatchMatchStereo.window_step 2' -FusionExtraArgs '--StereoFusion.fuse_prior_weight 1.0'
exit $LASTEXITCODE

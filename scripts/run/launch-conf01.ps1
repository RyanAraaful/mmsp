$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$stereo = "$LewolebaRoot/dense700/stereo"
$backup = "$stereo/backup_pre_conf01"
New-Item -ItemType Directory -Force "$backup/depth_maps" | Out-Null
New-Item -ItemType Directory -Force "$backup/normal_maps" | Out-Null
foreach ($f in @(Get-ChildItem "$stereo/depth_maps/*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$backup/depth_maps/" -Force }
foreach ($f in @(Get-ChildItem "$stereo/normal_maps/*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$backup/normal_maps/" -Force }
$colmap = "$ColmapExe"
$dense = "$LewolebaRoot/dense700"
$outdir = "$LewolebaRoot"
$t0 = Get-Date
& $colmap patch_match_stereo --workspace_path $dense --workspace_format COLMAP --PatchMatchStereo.max_image_size 700 --PatchMatchStereo.gpu_index 0 --PatchMatchStereo.window_radius 3 --PatchMatchStereo.window_step 2 --PatchMatchStereo.num_samples 10 --PatchMatchStereo.num_iterations 1 --PatchMatchStereo.min_triangulation_angle 1.0 --PatchMatchStereo.max_triangulation_angle 65.0 --PatchMatchStereo.geom_consistency 1 --PatchMatchStereo.geom_consistency_regularizer 0.3 --PatchMatchStereo.geom_consistency_max_cost 3.0 --PatchMatchStereo.filter 1 --PatchMatchStereo.filter_min_ncc 0.15 --PatchMatchStereo.filter_min_triangulation_angle 3.0 --PatchMatchStereo.filter_min_num_consistent 2 --PatchMatchStereo.filter_geom_consistency_max_cost 1.0 --PatchMatchStereo.pyramid_levels 1 --PatchMatchStereo.filter_min_confidence 0.1 --PatchMatchStereo.cache_size 4 2>&1 | Tee-Object "$outdir/log_patch_conf01.txt"
if ($LASTEXITCODE -ne 0) { throw "patch exit $LASTEXITCODE" }
$mapsWritten = @(Get-ChildItem "$dense/stereo/depth_maps/*.bin" -ErrorAction SilentlyContinue).Count
if ($mapsWritten -eq 0) { throw 'no depth maps written' }
& $colmap stereo_fusion --workspace_path $dense --workspace_format COLMAP --input_type geometric --output_path "$dense/fused_conf01.ply" --StereoFusion.max_image_size 700 --StereoFusion.min_num_pixels 3 --StereoFusion.max_reproj_error 4.0 --StereoFusion.max_depth_error 0.1 --StereoFusion.max_normal_error 20.0 --StereoFusion.check_num_images 30 --StereoFusion.fuse_prior_weight 1.0 --StereoFusion.cache_size 4 2>&1 | Tee-Object "$outdir/log_fusion_conf01.txt"
Select-String 'Number of fused|Elapsed time' "$outdir/log_patch_conf01.txt", "$outdir/log_fusion_conf01.txt"
'WALL TOTAL: {0}' -f ((Get-Date) - $t0)
Get-FileHash "$dense/fused_conf01.ply"
exit 0

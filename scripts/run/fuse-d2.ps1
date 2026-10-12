$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$colmap = "$ColmapExe"
$dense = "$LewolebaRoot/dense700"
$outdir = "$LewolebaRoot"
$t0 = Get-Date
& $colmap stereo_fusion --workspace_path $dense --workspace_format COLMAP --input_type geometric --output_path "$dense/fused_d2.ply" --StereoFusion.max_image_size 700 --StereoFusion.min_num_pixels 3 --StereoFusion.max_reproj_error 4.0 --StereoFusion.max_depth_error 0.1 --StereoFusion.max_normal_error 20.0 --StereoFusion.check_num_images 30 --StereoFusion.fuse_prior_weight 1.0 --StereoFusion.cache_size 4 2>&1 | Tee-Object "$outdir/log_fuse_d2.txt"
'T_EXIT: {0}' -f $LASTEXITCODE
Select-String 'Number of fused|Elapsed time' "$outdir/log_fuse_d2.txt"
'TOTAL_WALL: {0}' -f ((Get-Date) - $t0)
if (Test-Path "$dense/fused_d2.ply") { Get-FileHash "$dense/fused_d2.ply" }
exit 0

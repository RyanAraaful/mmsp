$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$colmap = "$ColmapExe"
$t0 = Get-Date
& $colmap stereo_fusion --workspace_path "$PrimaryRoot/dense700" --workspace_format COLMAP --input_type geometric --output_path "$PrimaryRoot/dense700/fused_d3.ply" --StereoFusion.max_image_size 700 --StereoFusion.min_num_pixels 3 --StereoFusion.max_reproj_error 6.0 --StereoFusion.max_depth_error 0.1 --StereoFusion.max_normal_error 20.0 --StereoFusion.check_num_images 30 --StereoFusion.fuse_prior_weight 1.0 --StereoFusion.cache_size 4 2>&1 | Tee-Object "$PrimaryRoot/log_fuse_d3.txt"
Select-String 'Number of fused|Elapsed time' "$PrimaryRoot/log_fuse_d3.txt"
& $colmap stereo_fusion --workspace_path "$SecondaryRoot/dense" --workspace_format COLMAP --input_type geometric --output_path "$SecondaryRoot/dense/fused_secondary_d3.ply" --StereoFusion.max_image_size 700 --StereoFusion.min_num_pixels 3 --StereoFusion.max_reproj_error 6.0 --StereoFusion.max_depth_error 0.1 --StereoFusion.max_normal_error 20.0 --StereoFusion.check_num_images 30 --StereoFusion.fuse_prior_weight 1.0 --StereoFusion.cache_size 4 2>&1 | Tee-Object "$SecondaryRoot/log_fuse_secondary_d3.txt"
Select-String 'Number of fused|Elapsed time' "$SecondaryRoot/log_fuse_secondary_d3.txt"
'TOTAL_WALL: {0}' -f ((Get-Date) - $t0)
exit 0

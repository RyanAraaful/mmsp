$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$colmap = "$ColmapExe"
$t0 = Get-Date
& $colmap stereo_fusion --workspace_path "$LewolebaRoot/dense700" --workspace_format COLMAP --input_type geometric --output_path "$LewolebaRoot/dense700/fused_d3.ply" --StereoFusion.max_image_size 700 --StereoFusion.min_num_pixels 3 --StereoFusion.max_reproj_error 6.0 --StereoFusion.max_depth_error 0.1 --StereoFusion.max_normal_error 20.0 --StereoFusion.check_num_images 30 --StereoFusion.fuse_prior_weight 1.0 --StereoFusion.cache_size 4 2>&1 | Tee-Object "$LewolebaRoot/log_fuse_d3.txt"
Select-String 'Number of fused|Elapsed time' "$LewolebaRoot/log_fuse_d3.txt"
& $colmap stereo_fusion --workspace_path "$MidaiRoot/dense" --workspace_format COLMAP --input_type geometric --output_path "$MidaiRoot/dense/fused_midai_d3.ply" --StereoFusion.max_image_size 700 --StereoFusion.min_num_pixels 3 --StereoFusion.max_reproj_error 6.0 --StereoFusion.max_depth_error 0.1 --StereoFusion.max_normal_error 20.0 --StereoFusion.check_num_images 30 --StereoFusion.fuse_prior_weight 1.0 --StereoFusion.cache_size 4 2>&1 | Tee-Object "$MidaiRoot/log_fuse_midai_d3.txt"
Select-String 'Number of fused|Elapsed time' "$MidaiRoot/log_fuse_midai_d3.txt"
'TOTAL_WALL: {0}' -f ((Get-Date) - $t0)
exit 0

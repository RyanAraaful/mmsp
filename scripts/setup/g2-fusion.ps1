$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$colmap = "$ColmapExe"
$dense = "$LewolebaRoot\dense"
& $colmap stereo_fusion --workspace_path $dense --workspace_format COLMAP --input_type geometric --output_path "$dense\fused.ply" --StereoFusion.max_image_size 1400 --StereoFusion.min_num_pixels 3 --StereoFusion.max_reproj_error 4.0 --StereoFusion.max_depth_error 0.05 --StereoFusion.max_normal_error 20.0 --StereoFusion.check_num_images 30 --StereoFusion.cache_size 4 2>&1 | Tee-Object "$LewolebaRoot\log_fusion.txt"
exit 0

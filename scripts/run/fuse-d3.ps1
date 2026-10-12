$ErrorActionPreference = 'Continue'
$env:CUDA_PATH = 'E:\dev\tools\cuda-env'
$env:CUDA_HOME = 'E:\dev\tools\cuda-env'
$env:CUDAToolkit_ROOT = 'E:\dev\tools\cuda-env'
$env:PATH = 'E:\dev\tools\cuda-env\bin;' + $env:PATH
$colmap = 'E:/dev/Colmap-Kernel/colmap/build-mx150/src/colmap/exe/colmap.exe'
$t0 = Get-Date
& $colmap stereo_fusion --workspace_path 'E:/dev/Lewoleba-15agustus/dense700' --workspace_format COLMAP --input_type geometric --output_path 'E:/dev/Lewoleba-15agustus/dense700/fused_d3.ply' --StereoFusion.max_image_size 700 --StereoFusion.min_num_pixels 3 --StereoFusion.max_reproj_error 6.0 --StereoFusion.max_depth_error 0.1 --StereoFusion.max_normal_error 20.0 --StereoFusion.check_num_images 30 --StereoFusion.fuse_prior_weight 1.0 --StereoFusion.cache_size 4 2>&1 | Tee-Object 'E:/dev/Lewoleba-15agustus/log_fuse_d3.txt'
Select-String 'Number of fused|Elapsed time' 'E:/dev/Lewoleba-15agustus/log_fuse_d3.txt'
& $colmap stereo_fusion --workspace_path 'E:/dev/Midai-14agustus/dense' --workspace_format COLMAP --input_type geometric --output_path 'E:/dev/Midai-14agustus/dense/fused_midai_d3.ply' --StereoFusion.max_image_size 700 --StereoFusion.min_num_pixels 3 --StereoFusion.max_reproj_error 6.0 --StereoFusion.max_depth_error 0.1 --StereoFusion.max_normal_error 20.0 --StereoFusion.check_num_images 30 --StereoFusion.fuse_prior_weight 1.0 --StereoFusion.cache_size 4 2>&1 | Tee-Object 'E:/dev/Midai-14agustus/log_fuse_midai_d3.txt'
Select-String 'Number of fused|Elapsed time' 'E:/dev/Midai-14agustus/log_fuse_midai_d3.txt'
'TOTAL_WALL: {0}' -f ((Get-Date) - $t0)
exit 0

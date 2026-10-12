$ErrorActionPreference = 'Continue'
$env:CUDA_PATH = 'E:\dev\tools\cuda-env'
$env:CUDA_HOME = 'E:\dev\tools\cuda-env'
$env:CUDAToolkit_ROOT = 'E:\dev\tools\cuda-env'
$env:PATH = 'E:\dev\tools\cuda-env\bin;' + $env:PATH
$colmap = 'E:/dev/Colmap-Kernel/colmap/build-mx150/src/colmap/exe/colmap.exe'
$dense = 'E:/dev/Lewoleba-15agustus/dense700'
$outdir = 'E:/dev/Lewoleba-15agustus'
$t0 = Get-Date
& $colmap stereo_fusion --workspace_path $dense --workspace_format COLMAP --input_type geometric --output_path "$dense/fused_d1base.ply" --StereoFusion.max_image_size 700 --StereoFusion.min_num_pixels 3 --StereoFusion.max_reproj_error 4.0 --StereoFusion.max_depth_error 0.05 --StereoFusion.max_normal_error 20.0 --StereoFusion.check_num_images 30 --StereoFusion.fuse_prior_weight 1.0 --StereoFusion.cache_size 4 2>&1 | Tee-Object "$outdir/log_fuse_d1base.txt"
'T0_EXIT: {0}' -f $LASTEXITCODE
& $colmap stereo_fusion --workspace_path $dense --workspace_format COLMAP --input_type geometric --output_path "$dense/fused_d1.ply" --StereoFusion.max_image_size 700 --StereoFusion.min_num_pixels 2 --StereoFusion.max_reproj_error 4.0 --StereoFusion.max_depth_error 0.05 --StereoFusion.max_normal_error 20.0 --StereoFusion.check_num_images 30 --StereoFusion.fuse_prior_weight 1.0 --StereoFusion.cache_size 4 2>&1 | Tee-Object "$outdir/log_fuse_d1.txt"
'T1_EXIT: {0}' -f $LASTEXITCODE
Select-String 'Number of fused|Elapsed time' "$outdir/log_fuse_d1base.txt", "$outdir/log_fuse_d1.txt"
'TOTAL_WALL: {0}' -f ((Get-Date) - $t0)
if (Test-Path "$dense/fused_d1.ply") { Get-FileHash "$dense/fused_d1.ply" }
exit 0

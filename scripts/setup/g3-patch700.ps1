$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$colmap = "$ColmapExe"
$dense = "$LewolebaRoot\dense700"
Copy-Item "$dense\stereo\patch-match.cfg" "$dense\stereo\patch-match.cfg.full" -Force
(Get-Content "$dense\stereo\patch-match.cfg.full") -replace '__auto__, 20', '__auto__, 8' | Out-File -Encoding ascii "$dense\stereo\patch-match.cfg"
$sampler = Start-Process powershell -ArgumentList '-NoProfile', '-Command', "while (Get-Process colmap -ErrorAction SilentlyContinue) { ((nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits) + ',' + (Get-Date -Format 'HH:mm:ss')) | Out-File "$LewolebaRoot/vram_700.csv" -Append; Start-Sleep 5 }" -PassThru
& $colmap patch_match_stereo --workspace_path $dense --workspace_format COLMAP --PatchMatchStereo.max_image_size 700 --PatchMatchStereo.gpu_index 0 --PatchMatchStereo.window_radius 5 --PatchMatchStereo.window_step 1 --PatchMatchStereo.num_samples 10 --PatchMatchStereo.num_iterations 4 --PatchMatchStereo.min_triangulation_angle 1.0 --PatchMatchStereo.max_triangulation_angle 65.0 --PatchMatchStereo.geom_consistency 1 --PatchMatchStereo.geom_consistency_regularizer 0.3 --PatchMatchStereo.geom_consistency_max_cost 3.0 --PatchMatchStereo.filter 1 --PatchMatchStereo.filter_min_ncc 0.15 --PatchMatchStereo.filter_min_triangulation_angle 3.0 --PatchMatchStereo.filter_min_num_consistent 2 --PatchMatchStereo.filter_geom_consistency_max_cost 1.0 --PatchMatchStereo.cache_size 4 2>&1 | Tee-Object "$LewolebaRoot\log_patch700.txt"
& $colmap stereo_fusion --workspace_path $dense --workspace_format COLMAP --input_type geometric --output_path "$dense\fused.ply" --StereoFusion.max_image_size 700 --StereoFusion.min_num_pixels 3 --StereoFusion.max_reproj_error 4.0 --StereoFusion.max_depth_error 0.05 --StereoFusion.max_normal_error 20.0 --StereoFusion.check_num_images 30 --StereoFusion.cache_size 4 2>&1 | Tee-Object "$LewolebaRoot\log_fusion700.txt"
Stop-Process -Id $sampler.Id -Force -ErrorAction SilentlyContinue
exit 0

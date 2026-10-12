$ErrorActionPreference = 'Continue'
$env:CUDA_PATH = 'E:\dev\tools\cuda-env'
$env:CUDA_HOME = 'E:\dev\tools\cuda-env'
$env:CUDAToolkit_ROOT = 'E:\dev\tools\cuda-env'
$env:PATH = 'E:\dev\tools\cuda-env\bin;' + $env:PATH
$colmap = 'E:\dev\Colmap-Kernel\colmap\build-mx150\src\colmap\exe\colmap.exe'
$dense = 'E:\dev\Lewoleba-15agustus\dense'
Copy-Item "$dense\stereo\patch-match.cfg.full" "$dense\stereo\patch-match.cfg" -Force
(Get-Content "$dense\stereo\patch-match.cfg") -replace '__auto__, 20', '__auto__, 6' | Out-File -Encoding ascii "$dense\stereo\patch-match.cfg"
$sampler = Start-Process powershell -ArgumentList '-NoProfile', '-Command', "while (Get-Process colmap -ErrorAction SilentlyContinue) { ((nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits) + ',' + (Get-Date -Format 'HH:mm:ss')) | Out-File 'E:/dev/Lewoleba-15agustus/vram_full.csv' -Append; Start-Sleep 5 }" -PassThru
& $colmap patch_match_stereo --workspace_path $dense --workspace_format COLMAP --PatchMatchStereo.max_image_size 1400 --PatchMatchStereo.gpu_index 0 --PatchMatchStereo.window_radius 5 --PatchMatchStereo.window_step 1 --PatchMatchStereo.num_samples 10 --PatchMatchStereo.num_iterations 4 --PatchMatchStereo.min_triangulation_angle 1.0 --PatchMatchStereo.max_triangulation_angle 15.0 --PatchMatchStereo.geom_consistency 1 --PatchMatchStereo.geom_consistency_regularizer 0.3 --PatchMatchStereo.geom_consistency_max_cost 3.0 --PatchMatchStereo.filter 1 --PatchMatchStereo.filter_min_ncc 0.15 --PatchMatchStereo.filter_min_triangulation_angle 3.0 --PatchMatchStereo.filter_min_num_consistent 2 --PatchMatchStereo.filter_geom_consistency_max_cost 1.0 --PatchMatchStereo.cache_size 4 --PatchMatchStereo.depth_min 15 --PatchMatchStereo.depth_max 100 2>&1 | Tee-Object 'E:\dev\Lewoleba-15agustus\log_patch_full.txt'
Stop-Process -Id $sampler.Id -Force -ErrorAction SilentlyContinue
exit 0

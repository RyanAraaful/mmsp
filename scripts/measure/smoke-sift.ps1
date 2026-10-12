$ErrorActionPreference = 'Continue'
$env:CUDA_PATH = 'E:\dev\tools\cuda-env'
$env:CUDA_HOME = 'E:\dev\tools\cuda-env'
$env:CUDAToolkit_ROOT = 'E:\dev\tools\cuda-env'
$env:PATH = 'E:\dev\tools\cuda-env\bin;' + $env:PATH
$colmap = 'E:/dev/Colmap-Kernel/colmap/build-mx150/src/colmap/exe/colmap.exe'
$smoke = 'E:/dev/Colmap-Kernel/smoke-test'
New-Item -ItemType Directory -Force "$smoke/images" | Out-Null
Copy-Item 'E:\Foto Udara\Midai\Photo Capture\14 Agustus 2025\dji_fly_20250814_073022_877_1755132223527_photo.jpg' "$smoke/images/" -Force
Copy-Item 'E:\Foto Udara\Midai\Photo Capture\14 Agustus 2025\dji_fly_20250814_073026_878_1755132222165_photo.jpg' "$smoke/images/" -Force
Copy-Item 'E:\Foto Udara\Midai\Photo Capture\14 Agustus 2025\dji_fly_20250814_073028_879_1755132220831_photo.jpg' "$smoke/images/" -Force
if (Test-Path "$smoke/database.db") { Remove-Item "$smoke/database.db" -Force }
& $colmap feature_extractor --database_path "$smoke/database.db" --image_path "$smoke/images" --ImageReader.single_camera 1 --FeatureExtraction.use_gpu 0 --SiftExtraction.max_num_features 2000 2>&1 | Tee-Object "$smoke/log_smoke.txt"
'SMOKE_EXIT: {0}' -f $LASTEXITCODE
Select-String 'ERROR|FATAL|Extracted|features' "$smoke/log_smoke.txt" | Select-Object -Last 8 Line
exit 0

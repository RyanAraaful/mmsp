$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$colmap = "$ColmapExe"
$smoke = "$RepoRoot/smoke-test-gpu"
New-Item -ItemType Directory -Force "$smoke/images" | Out-Null
Copy-Item "$SecondaryPhotos/dji_fly_20250814_073022_877_1755132223527_photo.jpg" "$smoke/images/" -Force
Copy-Item "$SecondaryPhotos/dji_fly_20250814_073026_878_1755132222165_photo.jpg" "$smoke/images/" -Force
Copy-Item "$SecondaryPhotos/dji_fly_20250814_073028_879_1755132220831_photo.jpg" "$smoke/images/" -Force
if (Test-Path "$smoke/database.db") { Remove-Item "$smoke/database.db" -Force }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $colmap feature_extractor --database_path "$smoke/database.db" --image_path "$smoke/images" --ImageReader.single_camera 1 --FeatureExtraction.use_gpu 0 --SiftExtraction.use_gpu_native 1 --SiftExtraction.max_num_features 2000 2>&1 | Tee-Object "$smoke/log_smoke_gpu.txt"
$code = $LASTEXITCODE
$sw.Stop()
'SMOKE_EXIT: {0}' -f $code
'SMOKE_WALL_S: {0:N1}' -f $sw.Elapsed.TotalSeconds
Select-String 'ERROR|FATAL|Extracted|features|not implemented' "$smoke/log_smoke_gpu.txt" | Select-Object -Last 8 Line
exit $code

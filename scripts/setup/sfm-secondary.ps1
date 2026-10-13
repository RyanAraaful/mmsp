$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$colmap = "$ColmapExe"
$proj = $SecondaryRoot
$src = $SecondaryPhotos
# Fairness vs OpenSfM (duel Secondary 51): samakan resolusi proses (OpenSfM
# feature_process_size default 2048; COLMAP SIFT default 3200) + budget fitur
# (OpenSfM aktual ~5rb/foto) via 2 flag di bawah. SIFT vs HAHOG + cara pilih
# pasangan memang beda — itu yang diadu, bukan disamakan (dicatat di MODS.md).
mkdir "$proj\images" -Force | Out-Null
Copy-Item "$src\*.jpg" "$proj\images\" -Force # top level saja; subdir Duplikat\ dikecualikan
Write-Host ("images=" + @(Get-ChildItem "$proj\images\*.jpg").Count)
& $colmap feature_extractor --database_path "$proj\database.db" --image_path "$proj\images" --ImageReader.single_camera 1 --FeatureExtraction.max_image_size 2048 --SiftExtraction.max_num_features 5000 --FeatureExtraction.use_gpu 0 --FeatureExtraction.num_threads -1 2>&1 | Tee-Object "$proj\log_extract.txt"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $colmap sequential_matcher --database_path "$proj\database.db" --SequentialMatching.overlap 10 --FeatureMatching.use_gpu 0 --FeatureMatching.num_threads -1 2>&1 | Tee-Object "$proj\log_match.txt"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
mkdir "$proj\sparse" -Force | Out-Null
& $colmap mapper --database_path "$proj\database.db" --image_path "$proj\images" --output_path "$proj\sparse" 2>&1 | Tee-Object "$proj\log_mapper.txt"
exit $LASTEXITCODE

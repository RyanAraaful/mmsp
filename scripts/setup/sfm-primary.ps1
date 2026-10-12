$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$colmap = "$ColmapExe"
$proj = "$PrimaryRoot"
& $colmap feature_extractor --database_path "$proj\database.db" --image_path "$proj\images" --ImageReader.single_camera 1 --FeatureExtraction.use_gpu 0 --FeatureExtraction.num_threads -1 2>&1 | Tee-Object "$proj\log_extract.txt"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $colmap sequential_matcher --database_path "$proj\database.db" --SequentialMatching.overlap 10 --FeatureMatching.use_gpu 0 --FeatureMatching.num_threads -1 2>&1 | Tee-Object "$proj\log_match.txt"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
mkdir "$proj\sparse" -Force
& $colmap mapper --database_path "$proj\database.db" --image_path "$proj\images" --output_path "$proj\sparse" 2>&1 | Tee-Object "$proj\log_mapper.txt"
exit $LASTEXITCODE

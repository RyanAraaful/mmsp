$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$colmap = "$ColmapExe"
& $colmap image_undistorter --image_path "$PrimaryRoot/images" --input_path "$PrimaryRoot/sparse/0" --output_path "$PrimaryRoot/dense700" --output_type COLMAP --max_image_size 700 2>&1 | Tee-Object "$PrimaryRoot/log_undistort700.txt"
exit 0

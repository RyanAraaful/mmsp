$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$colmap = "$ColmapExe"
& $colmap image_undistorter --image_path "$LewolebaRoot/images" --input_path "$LewolebaRoot/sparse/0" --output_path "$LewolebaRoot/dense700" --output_type COLMAP --max_image_size 700 2>&1 | Tee-Object "$LewolebaRoot/log_undistort700.txt"
exit 0

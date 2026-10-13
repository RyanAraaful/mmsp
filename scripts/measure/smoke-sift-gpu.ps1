param([switch]$DetectOnly)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$colmap = "$ColmapExe"
$smoke = "$RepoRoot/smoke-test-gpu"
New-Item -ItemType Directory -Force "$smoke/images" | Out-Null
Copy-Item "$SecondaryPhotos/dji_fly_20250814_073022_877_1755132223527_photo.jpg" "$smoke/images/" -Force
Copy-Item "$SecondaryPhotos/dji_fly_20250814_073026_878_1755132222165_photo.jpg" "$smoke/images/" -Force
Copy-Item "$SecondaryPhotos/dji_fly_20250814_073028_879_1755132220831_photo.jpg" "$smoke/images/" -Force

function Get-FeatureCounts($log) {
  $m = @{}
  $cur = ''
  foreach ($line in (Get-Content $log)) {
    if ($line -match 'Name:\s+(\S+\.jpg)') { $cur = $Matches[1] }
    if ($line -match 'Features:\s+(\d+)' -and $cur -ne '') { $m[$cur] = [int]$Matches[1]; $cur = '' }
  }
  return $m
}

if ($DetectOnly) {
  # Task 2 detection-only mode: GPU detection (env-gated) vs VLFeat CPU with
  # max_num_orientations 1 (one keypoint per DoG extremum on both sides).
  # NOTE: colmap has no `database_reader` command; counts come from the
  # feature_extractor log `Features:` lines (the exact values written to the DB).
  $env:COLMAP_SIFT_GPU_NATIVE_DETECT_ONLY = '1'
  if (Test-Path "$smoke/database.db") { Remove-Item "$smoke/database.db" -Force }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $colmap feature_extractor --database_path "$smoke/database.db" --image_path "$smoke/images" --ImageReader.single_camera 1 --FeatureExtraction.use_gpu 0 --SiftExtraction.use_gpu_native 1 --SiftExtraction.max_num_features 2000 --SiftExtraction.max_num_orientations 1 2>&1 | Tee-Object "$smoke/log_smoke_gpu_detect.txt"
  $gcode = $LASTEXITCODE
  $sw.Stop()
  $gwall = $sw.Elapsed.TotalSeconds
  'SMOKE_GPU_EXIT: {0}' -f $gcode
  'SMOKE_GPU_WALL_S: {0:N1}' -f $gwall
  if ($gcode -ne 0) {
    Select-String 'ERROR|FATAL|not implemented' "$smoke/log_smoke_gpu_detect.txt" | Select-Object -Last 5 Line
    exit $gcode
  }
  $cpudb = "$smoke/database_cpu_detect.db"
  if (Test-Path $cpudb) { Remove-Item $cpudb -Force }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $colmap feature_extractor --database_path $cpudb --image_path "$smoke/images" --ImageReader.single_camera 1 --FeatureExtraction.use_gpu 0 --SiftExtraction.max_num_features 2000 --SiftExtraction.max_num_orientations 1 2>&1 | Tee-Object "$smoke/log_smoke_cpu_detect.txt"
  $ccode = $LASTEXITCODE
  $sw.Stop()
  $cwall = $sw.Elapsed.TotalSeconds
  'SMOKE_CPU_EXIT: {0}' -f $ccode
  'SMOKE_CPU_WALL_S: {0:N1}' -f $cwall
  $g = Get-FeatureCounts "$smoke/log_smoke_gpu_detect.txt"
  $c = Get-FeatureCounts "$smoke/log_smoke_cpu_detect.txt"
  $ok = $true
  foreach ($k in $c.Keys) {
    $gv = $g[$k]; $cv = $c[$k]
    if ($null -eq $gv) { 'MISSING_GPU: {0}' -f $k; $ok = $false; continue }
    $tol = if ($cv -eq 0) { $gv -eq 0 } else { [Math]::Abs($gv - $cv) / $cv -le 0.15 }
    'PHOTO {0} gpu={1} cpu={2} {3}' -f $k, $gv, $cv, ($(if ($tol) { 'PASS' } else { 'FAIL' }))
    if (-not $tol) { $ok = $false }
  }
  if ($ok) { 'DETECT_COMPARE: PASS' } else { 'DETECT_COMPARE: FAIL' }
  exit $(if ($ok -and $ccode -eq 0) { 0 } else { 1 })
}

if (Test-Path "$smoke/database.db") { Remove-Item "$smoke/database.db" -Force }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $colmap feature_extractor --database_path "$smoke/database.db" --image_path "$smoke/images" --ImageReader.single_camera 1 --FeatureExtraction.use_gpu 0 --SiftExtraction.use_gpu_native 1 --SiftExtraction.max_num_features 2000 2>&1 | Tee-Object "$smoke/log_smoke_gpu.txt"
$code = $LASTEXITCODE
$sw.Stop()
'SMOKE_EXIT: {0}' -f $code
'SMOKE_WALL_S: {0:N1}' -f $sw.Elapsed.TotalSeconds
Select-String 'ERROR|FATAL|Extracted|features|not implemented' "$smoke/log_smoke_gpu.txt" | Select-Object -Last 8 Line
exit $code

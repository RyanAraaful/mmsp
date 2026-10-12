$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$exe = "$MetricsExe"
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe "$LewolebaRoot/dense700/fused_d3.ply" "$LewolebaRoot/openmvs/scene_dense.ply" --pgm "$LewolebaRoot/metrics_d3" 2>&1 | Tee-Object "$LewolebaRoot/metrics_d3.txt"
& $exe "$MidaiRoot/dense/fused_midai_d3.ply" "$MidaiRoot/openmvs/scene_dense.ply" --pgm "$MidaiRoot/metrics_midai_d3" 2>&1 | Tee-Object "$MidaiRoot/metrics_midai_d3.txt"
exit 0

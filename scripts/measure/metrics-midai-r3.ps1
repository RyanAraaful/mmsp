$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$exe = "$MetricsExe"
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe "$MidaiRoot/dense/fused_midai_r3.ply" "$MidaiRoot/openmvs/scene_dense.ply" --pgm "$MidaiRoot/metrics_midai_r3" 2>&1 | Tee-Object "$MidaiRoot/metrics_midai_r3.txt"
exit 0

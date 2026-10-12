$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$exe = "$MetricsExe"
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe "$PrimaryRoot/dense700/fused_d2.ply" "$PrimaryRoot/openmvs/scene_dense.ply" --pgm "$PrimaryRoot/metrics_d2" 2>&1 | Tee-Object "$PrimaryRoot/metrics_d2.txt"
exit 0

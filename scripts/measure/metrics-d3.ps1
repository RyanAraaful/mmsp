$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$exe = "$MetricsExe"
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe "$PrimaryRoot/dense700/fused_d3.ply" "$PrimaryRoot/openmvs/scene_dense.ply" --pgm "$PrimaryRoot/metrics_d3" 2>&1 | Tee-Object "$PrimaryRoot/metrics_d3.txt"
& $exe "$SecondaryRoot/dense/fused_secondary_d3.ply" "$SecondaryRoot/openmvs/scene_dense.ply" --pgm "$SecondaryRoot/metrics_secondary_d3" 2>&1 | Tee-Object "$SecondaryRoot/metrics_secondary_d3.txt"
exit 0

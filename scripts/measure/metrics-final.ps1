$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$exe = "$MetricsExe"
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe "$PrimaryRoot/dense700/fused_reuse2.ply" "$PrimaryRoot/openmvs/scene_dense.ply" --pgm "$PrimaryRoot/metrics_reuse2" 2>&1 | Tee-Object "$PrimaryRoot/metrics_reuse2.txt"
& $exe "$SecondaryRoot/dense/fused_secondary_b64.ply" "$SecondaryRoot/openmvs/scene_dense.ply" --pgm "$SecondaryRoot/metrics_secondary_b64" 2>&1 | Tee-Object "$SecondaryRoot/metrics_secondary_b64.txt"
exit 0

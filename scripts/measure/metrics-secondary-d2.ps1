$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$exe = "$MetricsExe"
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe "$SecondaryRoot/dense/fused_secondary_d2.ply" "$SecondaryRoot/openmvs/scene_dense.ply" --pgm "$SecondaryRoot/metrics_secondary_d2" 2>&1 | Tee-Object "$SecondaryRoot/metrics_secondary_d2.txt"
exit 0

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$exe = "$MetricsExe"
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe "$SecondaryRoot/dense/fused_secondary_r3.ply" "$SecondaryRoot/openmvs/scene_dense.ply" --pgm "$SecondaryRoot/metrics_secondary_r3" 2>&1 | Tee-Object "$SecondaryRoot/metrics_secondary_r3.txt"
exit 0

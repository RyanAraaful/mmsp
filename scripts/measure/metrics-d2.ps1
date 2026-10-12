$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$exe = "$MetricsExe"
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe "$LewolebaRoot/dense700/fused_d2.ply" "$LewolebaRoot/openmvs/scene_dense.ply" --pgm "$LewolebaRoot/metrics_d2" 2>&1 | Tee-Object "$LewolebaRoot/metrics_d2.txt"
exit 0

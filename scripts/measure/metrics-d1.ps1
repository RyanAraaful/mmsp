$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$exe = "$MetricsExe"
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe "$PrimaryRoot/dense700/fused_d1.ply" "$PrimaryRoot/openmvs/scene_dense.ply" 2>&1 | Tee-Object "$PrimaryRoot/metrics_d1.txt"
exit 0

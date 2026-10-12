$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$exe = "$MetricsExe"
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe "$LewolebaRoot/dense700/fused_d1.ply" "$LewolebaRoot/openmvs/scene_dense.ply" 2>&1 | Tee-Object "$LewolebaRoot/metrics_d1.txt"
exit 0

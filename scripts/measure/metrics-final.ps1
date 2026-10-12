$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
$exe = "$MetricsExe"
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe "$LewolebaRoot/dense700/fused_reuse2.ply" "$LewolebaRoot/openmvs/scene_dense.ply" --pgm "$LewolebaRoot/metrics_reuse2" 2>&1 | Tee-Object "$LewolebaRoot/metrics_reuse2.txt"
& $exe "$MidaiRoot/dense/fused_midai_b64.ply" "$MidaiRoot/openmvs/scene_dense.ply" --pgm "$MidaiRoot/metrics_midai_b64" 2>&1 | Tee-Object "$MidaiRoot/metrics_midai_b64.txt"
exit 0

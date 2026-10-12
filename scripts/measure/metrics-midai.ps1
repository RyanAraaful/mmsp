$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
& "$MetricsExe" "$MidaiRoot/dense/fused_midai_ws2.ply" "$MidaiRoot/openmvs/scene_dense.ply" 2>&1 | Tee-Object "$MidaiRoot/metrics_midai.txt"
exit $LASTEXITCODE

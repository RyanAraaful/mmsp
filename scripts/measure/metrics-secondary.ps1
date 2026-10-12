$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
& "$MetricsExe" "$SecondaryRoot/dense/fused_secondary_ws2.ply" "$SecondaryRoot/openmvs/scene_dense.ply" 2>&1 | Tee-Object "$SecondaryRoot/metrics_secondary.txt"
exit $LASTEXITCODE

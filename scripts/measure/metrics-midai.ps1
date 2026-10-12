$ErrorActionPreference = 'Stop'
& 'E:/dev/Colmap-Kernel/tools/metrics.exe' 'E:/dev/Midai-14agustus/dense/fused_midai_ws2.ply' 'E:/dev/Midai-14agustus/openmvs/scene_dense.ply' 2>&1 | Tee-Object 'E:/dev/Midai-14agustus/metrics_midai.txt'
exit $LASTEXITCODE

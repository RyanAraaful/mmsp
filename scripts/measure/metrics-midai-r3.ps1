$ErrorActionPreference = 'Stop'
$exe = 'E:/dev/Colmap-Kernel/tools/metrics.exe'
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe 'E:/dev/Midai-14agustus/dense/fused_midai_r3.ply' 'E:/dev/Midai-14agustus/openmvs/scene_dense.ply' --pgm 'E:/dev/Midai-14agustus/metrics_midai_r3' 2>&1 | Tee-Object 'E:/dev/Midai-14agustus/metrics_midai_r3.txt'
exit 0

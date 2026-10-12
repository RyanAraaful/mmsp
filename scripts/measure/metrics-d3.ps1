$ErrorActionPreference = 'Stop'
$exe = 'E:/dev/Colmap-Kernel/tools/metrics.exe'
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe 'E:/dev/Lewoleba-15agustus/dense700/fused_d3.ply' 'E:/dev/Lewoleba-15agustus/openmvs/scene_dense.ply' --pgm 'E:/dev/Lewoleba-15agustus/metrics_d3' 2>&1 | Tee-Object 'E:/dev/Lewoleba-15agustus/metrics_d3.txt'
& $exe 'E:/dev/Midai-14agustus/dense/fused_midai_d3.ply' 'E:/dev/Midai-14agustus/openmvs/scene_dense.ply' --pgm 'E:/dev/Midai-14agustus/metrics_midai_d3' 2>&1 | Tee-Object 'E:/dev/Midai-14agustus/metrics_midai_d3.txt'
exit 0

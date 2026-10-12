$ErrorActionPreference = 'Stop'
$exe = 'E:/dev/Colmap-Kernel/tools/metrics.exe'
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe 'E:/dev/Lewoleba-15agustus/dense700/fused_d2.ply' 'E:/dev/Lewoleba-15agustus/openmvs/scene_dense.ply' --pgm 'E:/dev/Lewoleba-15agustus/metrics_d2' 2>&1 | Tee-Object 'E:/dev/Lewoleba-15agustus/metrics_d2.txt'
exit 0

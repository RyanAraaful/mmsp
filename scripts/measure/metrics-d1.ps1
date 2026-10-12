$ErrorActionPreference = 'Stop'
$exe = 'E:/dev/Colmap-Kernel/tools/metrics.exe'
if (!(Test-Path $exe)) { throw 'metrics.exe missing' }
& $exe 'E:/dev/Lewoleba-15agustus/dense700/fused_d1.ply' 'E:/dev/Lewoleba-15agustus/openmvs/scene_dense.ply' 2>&1 | Tee-Object 'E:/dev/Lewoleba-15agustus/metrics_d1.txt'
exit 0

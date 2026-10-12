$ErrorActionPreference = 'Continue'
$env:CUDA_PATH = 'E:\dev\tools\cuda-env'
$env:CUDA_HOME = 'E:\dev\tools\cuda-env'
$env:CUDAToolkit_ROOT = 'E:\dev\tools\cuda-env'
$env:PATH = 'E:\dev\tools\cuda-env\bin;' + $env:PATH
$colmap = 'E:\dev\Colmap-Kernel\colmap\build-mx150\src\colmap\exe\colmap.exe'
& $colmap image_undistorter --image_path 'E:/dev/Lewoleba-15agustus/images' --input_path 'E:/dev/Lewoleba-15agustus/sparse/0' --output_path 'E:/dev/Lewoleba-15agustus/dense700' --output_type COLMAP --max_image_size 700 2>&1 | Tee-Object 'E:/dev/Lewoleba-15agustus/log_undistort700.txt'
exit 0

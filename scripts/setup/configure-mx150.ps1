$ErrorActionPreference = 'Stop'
# Load MSVC env (vcvars64) into this process
$vc = cmd /c '"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >NUL && set'
foreach ($line in $vc) {
  $i = $line.IndexOf('=')
  if ($i -gt 0) { Set-Item "env:$($line.Substring(0, $i))" $line.Substring($i + 1) }
}
$env:CUDA_PATH = 'E:\dev\tools\cuda-env'
$env:CUDA_HOME = 'E:\dev\tools\cuda-env'
$env:CUDAToolkit_ROOT = 'E:\dev\tools\cuda-env'
$env:PATH = 'E:\dev\tools\cuda-env\bin;' + $env:PATH
Set-Location 'E:\dev\Colmap-Kernel\colmap'
$cmake = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
& $cmake -B build-mx150 -G Ninja `
  -DCMAKE_TOOLCHAIN_FILE=E:\dev\vcpkg\scripts\buildsystems\vcpkg.cmake `
  -DCUDA_ENABLED=ON -DGUI_ENABLED=OFF -DCGAL_ENABLED=OFF -DLSD_ENABLED=OFF `
  -DTESTS_ENABLED=OFF -DDOWNLOAD_ENABLED=OFF -DCASPAR_ENABLED=OFF -DIPO_ENABLED=OFF `
  -DFETCH_POSELIB=ON -DFETCH_FAISS=ON `
  -DCMAKE_CUDA_ARCHITECTURES=61 -DCMAKE_BUILD_TYPE=Release
exit $LASTEXITCODE

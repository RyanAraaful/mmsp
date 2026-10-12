$ErrorActionPreference = 'Continue'
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
Set-Location 'E:\dev\openMVS'
$cmake = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
# SIFTGPU=OFF (lisensi non-profit, tak dipakai DensifyPointCloud).
# VIEWER/PYTHON/TESTS=OFF (tak perlu untuk benchmark batch; hemat build).
# CGAL tetap ON (dependensi inti Mesh; pemakaian internal benchmark saja,
# tidak didistribusikan). cGAL/GPL tidak masuk binary COLMAP kita.
& $cmake -B build-mx150 -G Ninja `
  -DCMAKE_TOOLCHAIN_FILE=E:\dev\vcpkg\scripts\buildsystems\vcpkg.cmake `
  -DOpenMVS_USE_CUDA=ON -DOpenMVS_USE_SIFTGPU=OFF -DOpenMVS_BUILD_VIEWER=OFF `
  -DOpenMVS_USE_PYTHON=OFF -DOpenMVS_ENABLE_TESTS=OFF -DOpenMVS_ENABLE_IPO=OFF `
  -DOpenMVS_USE_BREAKPAD=OFF `
  -DCMAKE_CUDA_ARCHITECTURES=61 -DCMAKE_BUILD_TYPE=Release
exit $LASTEXITCODE

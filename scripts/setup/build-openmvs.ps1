$ErrorActionPreference = 'Continue'
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
& $cmake --build build-mx150 --config Release --parallel 6 --target DensifyPointCloud InterfaceCOLMAP
exit $LASTEXITCODE

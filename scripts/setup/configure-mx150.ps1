$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
# Load MSVC env (vcvars64) into this process
$vc = cmd /c "`"$VsVcvarsBat`" >NUL && set"
foreach ($line in $vc) {
  $i = $line.IndexOf('=')
  if ($i -gt 0) { Set-Item "env:$($line.Substring(0, $i))" $line.Substring($i + 1) }
}
Set-Location "$RepoRoot\colmap"
$cmake = "$CMakeExe"
& $cmake -B build-mx150 -G Ninja `
  "-DCMAKE_TOOLCHAIN_FILE=$VcpkgRoot/scripts/buildsystems/vcpkg.cmake" `
  -DCUDA_ENABLED=ON -DGUI_ENABLED=OFF -DCGAL_ENABLED=OFF -DLSD_ENABLED=OFF `
  -DTESTS_ENABLED=OFF -DDOWNLOAD_ENABLED=OFF -DCASPAR_ENABLED=OFF -DIPO_ENABLED=OFF `
  -DFETCH_POSELIB=ON -DFETCH_FAISS=ON `
  -DCMAKE_CUDA_ARCHITECTURES=61 -DCMAKE_BUILD_TYPE=Release
exit $LASTEXITCODE

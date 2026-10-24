[CmdletBinding()]
param(
  [ValidatePattern('^\d+(;\d+)*$')][string]$CudaArchitectures = '61',
  [ValidatePattern('^[A-Za-z0-9_-][A-Za-z0-9_.-]*$')][string]$BuildDirectory = 'build-mx150-final',
  [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$VcpkgTargetTriplet = 'x64-windows-static',
  [string]$NinjaExe,
  [string]$VcpkgInstalledDir
)

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
if ([string]::IsNullOrWhiteSpace($NinjaExe)) {
  $ninjaCommand = Get-Command ninja.exe -ErrorAction SilentlyContinue
  if ($ninjaCommand) { $NinjaExe = $ninjaCommand.Source }
}
if ([string]::IsNullOrWhiteSpace($NinjaExe) -or -not (Test-Path -LiteralPath $NinjaExe -PathType Leaf)) {
  throw 'Ninja was not found. Add ninja.exe to PATH or pass -NinjaExe.'
}
$configureArgs = @(
  # Remove any unverified developer overrides retained in an existing cache.
  '-U', 'FETCHCONTENT_SOURCE_DIR_POSELIB', '-U', 'FETCHCONTENT_SOURCE_DIR_FAISS',
  '-B', $BuildDirectory, '-G', 'Ninja', "-DCMAKE_MAKE_PROGRAM=$([IO.Path]::GetFullPath($NinjaExe))",
  "-DCMAKE_TOOLCHAIN_FILE=$VcpkgRoot/scripts/buildsystems/vcpkg.cmake",
  "-DVCPKG_TARGET_TRIPLET=$VcpkgTargetTriplet",
  '-DVCPKG_MANIFEST_NO_DEFAULT_FEATURES=ON',
  '-DCUDA_ENABLED=ON', '-DGUI_ENABLED=OFF', '-DCGAL_ENABLED=OFF', '-DLSD_ENABLED=OFF',
  '-DTESTS_ENABLED=OFF', '-DDOWNLOAD_ENABLED=OFF', '-DCASPAR_ENABLED=OFF', '-DIPO_ENABLED=OFF',
  '-DFETCH_POSELIB=ON', '-DFETCH_FAISS=ON', '-DFAISS_ENABLE_MKL=OFF',
  '-DONNX_ENABLED=OFF',
  '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>',
  "-DCMAKE_CUDA_ARCHITECTURES=$CudaArchitectures", '-DCMAKE_BUILD_TYPE=Release'
)
if (-not [string]::IsNullOrWhiteSpace($VcpkgInstalledDir)) {
  $configureArgs += "-DVCPKG_INSTALLED_DIR=$([IO.Path]::GetFullPath($VcpkgInstalledDir))"
  $configureArgs += '-DVCPKG_MANIFEST_INSTALL=OFF'
}
& $cmake @configureArgs
exit $LASTEXITCODE

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$vc = cmd /c "`"$VsVcvarsBat`" >NUL && set"
foreach ($line in $vc) {
  $i = $line.IndexOf('=')
  if ($i -gt 0) { Set-Item "env:$($line.Substring(0, $i))" $line.Substring($i + 1) }
}
Set-Location $OpenMVSRoot
$cmake = "$CMakeExe"
& $cmake --build build-mx150 --config Release --parallel 6 --target DensifyPointCloud InterfaceCOLMAP
exit $LASTEXITCODE

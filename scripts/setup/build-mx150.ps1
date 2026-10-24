[CmdletBinding()]
param(
  [ValidatePattern('^[A-Za-z0-9_-][A-Za-z0-9_.-]*$')][string]$BuildDirectory = 'build-mx150-final'
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
& $cmake --build $BuildDirectory --config Release --parallel 6
exit $LASTEXITCODE

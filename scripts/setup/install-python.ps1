# Creates the Python 3.11 prefix env for the OpenSfM duel (plan Task 1).
# Paths come from env.local.ps1 ($MicromambaExe, $PyEnv); no machine paths here.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
if ([string]::IsNullOrEmpty($MicromambaExe)) {
  throw 'MicromambaExe is not set. See env.local.example.ps1.'
}
if ([string]::IsNullOrEmpty($PyEnv)) {
  throw 'PyEnv is not set. See env.local.example.ps1.'
}
if (-not (Test-Path $MicromambaExe)) {
  throw "MicromambaExe not found: $MicromambaExe"
}
$py = Join-Path $PyEnv 'python.exe'
if (Test-Path $py) {
  $v = (& $py --version 2>&1).ToString().Trim()
  Write-Host "existing: $v at $PyEnv"
  if ($v -match '^Python 3\.11\.') { exit 0 }
  throw "Existing env is not Python 3.11: $v (remove $PyEnv or fix PyEnv)"
}
& $MicromambaExe create -p $PyEnv -y python=3.11
if ($LASTEXITCODE -ne 0) {
  throw "micromamba create failed with exit $LASTEXITCODE (transient? retry once)"
}
& $py --version

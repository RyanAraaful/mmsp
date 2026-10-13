# Installs OpenSfM/OpenSfM@master (BSD-2-Clause) per doc/building.md (plan Task 2).
# Lock env (conda-win-64.lock, python 3.10) created at $PyEnv via micromamba,
# then pip install -e . Probes: import opensfm + opensfm_main.py --help.
# No machine paths here; everything comes from env.local.ps1 via scripts/env.ps1.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')
if ([string]::IsNullOrEmpty($MicromambaExe)) {
  throw 'MicromambaExe is not set. See env.local.example.ps1.'
}
if ([string]::IsNullOrEmpty($PyEnv)) {
  throw 'PyEnv is not set. See env.local.example.ps1.'
}
if ([string]::IsNullOrEmpty($OpenSfMRoot)) {
  throw 'OpenSfMRoot is not set. See env.local.example.ps1.'
}
if (-not (Test-Path $MicromambaExe)) {
  throw "MicromambaExe not found: $MicromambaExe"
}
if (-not (Test-Path (Join-Path $OpenSfMRoot 'doc/building.md'))) {
  throw "OpenSfM checkout not found at $OpenSfMRoot"
}
$py = Join-Path $PyEnv 'python.exe'
if (-not (Test-Path $py)) {
  & $MicromambaExe create -p $PyEnv --file (Join-Path $OpenSfMRoot 'conda-win-64.lock') -y
  if ($LASTEXITCODE -ne 0) {
    throw "micromamba create from lock failed with exit $LASTEXITCODE"
  }
} else {
  Write-Host "env exists, skipping create: $PyEnv"
}
# Run everything inside the env (micromamba run = conda activate semantics:
# CONDA_PREFIX + DLL paths) and hand the env prefix to CMake so custom
# find-modules (FindGflags etc.) locate the lock-provided dependencies.
$env:CMAKE_PREFIX_PATH = (Join-Path $PyEnv 'Library')
function Invoke-EnvPython {
  & $MicromambaExe run -p $PyEnv python @args
  if ($LASTEXITCODE -ne 0) {
    throw "env python failed: python $($args -join ' ')"
  }
}
Invoke-EnvPython -m pip install -e $OpenSfMRoot
Invoke-EnvPython -c "import opensfm; print('opensfm import OK:', opensfm.__file__)"
Invoke-EnvPython (Join-Path $OpenSfMRoot 'bin/opensfm_main.py') --help

# MMSP machine environment — sourced by every script in scripts/.
# Resolves repo-relative paths automatically; machine-specific values come
# from env.local.ps1 (gitignored) or MMSP_* environment overrides.
$RepoRoot = Split-Path $PSScriptRoot -Parent
$ColmapExe = Join-Path $RepoRoot 'colmap/build-mx150/src/colmap/exe/colmap.exe'
$MetricsExe = Join-Path $RepoRoot 'tools/metrics.exe'

$__localEnv = Join-Path $RepoRoot 'env.local.ps1'
if (Test-Path $__localEnv) { . $__localEnv }
if ($env:MMSP_CUDA_HOME) { $CudaEnv = $env:MMSP_CUDA_HOME }
if ($env:MMSP_LEWOLEBA_ROOT) { $LewolebaRoot = $env:MMSP_LEWOLEBA_ROOT }
if ($env:MMSP_MIDAI_ROOT) { $MidaiRoot = $env:MMSP_MIDAI_ROOT }

if ([string]::IsNullOrEmpty($CudaEnv)) {
  throw 'CudaEnv is not set. Copy env.local.example.ps1 to env.local.ps1 and fill in your paths.'
}
$env:CUDA_PATH = $CudaEnv
$env:CUDA_HOME = $CudaEnv
$env:CUDAToolkit_ROOT = $CudaEnv
$env:PATH = (Join-Path $CudaEnv 'bin') + ';' + $env:PATH

foreach ($__v in @('LewolebaRoot','MidaiRoot','MidaiPhotos','OpenMVSRoot','VcpkgRoot','VsVcvarsBat','CMakeExe','NsysExe','NcuExe','CloudCompareDir')) {
  if ([string]::IsNullOrEmpty((Get-Variable $__v -ValueOnly -ErrorAction SilentlyContinue))) {
    Write-Warning "$__v is not set (see env.local.example.ps1). Scripts needing it will fail."
  }
}

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateSet('cpu', 'native-cuda')][string]$Extractor,
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')

$imagesPath = Join-Path $PrimaryRoot 'images'
$colmapExe = Join-Path $RepoRoot 'colmap/build-mx150-final/src/colmap/exe/colmap.exe'
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path $PrimaryRoot ('sparse-sift-117-' + $Extractor + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if (-not (Test-Path -LiteralPath $imagesPath -PathType Container)) { throw 'PrimaryRoot/images is unavailable.' }
if (-not (Test-Path -LiteralPath $colmapExe -PathType Leaf)) { throw 'The final branch COLMAP executable is unavailable.' }
$photoCount = @(Get-ChildItem -LiteralPath $imagesPath -File -Recurse | Where-Object { $_.Extension -match '^\.(jpg|jpeg)$' }).Count
if ($photoCount -ne 117) { throw "Expected the reference dataset to contain 117 JPG/JPEG photos; found $photoCount." }

Write-Host "SPARSE_SIFT_EXTRACTOR=$Extractor"
Write-Host "PRIMARY_PHOTO_COUNT=$photoCount"
Write-Host "COLMAP_SHA256=$((Get-FileHash -LiteralPath $colmapExe -Algorithm SHA256).Hash)"
$runnerScript = Join-Path $PSScriptRoot '../run/process-drone.ps1'
if ($Extractor -eq 'native-cuda') {
  & $runnerScript -ImagesPath $imagesPath -OutputDir $OutputDir -ColmapExe $colmapExe -NativeGpuSift
} else {
  & $runnerScript -ImagesPath $imagesPath -OutputDir $OutputDir -ColmapExe $colmapExe
}
if (-not $?) { exit 1 }
exit 0

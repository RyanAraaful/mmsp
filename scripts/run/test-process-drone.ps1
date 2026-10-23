$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('mmsp-process-drone-' + [guid]::NewGuid().ToString('N'))
$imagesPath = Join-Path $testRoot 'images'
$outputDir = Join-Path $testRoot 'output'
$scriptPath = Join-Path $PSScriptRoot 'process-drone.ps1'

function Invoke-Pipeline([string]$InputPath, [string]$TargetOutput) {
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
  $startInfo.UseShellExecute = $false
  $startInfo.Arguments = (@('-NoProfile', '-File', $scriptPath, '-ImagesPath', $InputPath, '-OutputDir', $TargetOutput) |
    ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
  $process = [Diagnostics.Process]::Start($startInfo)
  $process.WaitForExit()
  return $process.ExitCode
}

$null = New-Item -ItemType Directory -Path $imagesPath -Force
$null = New-Item -ItemType Directory -Path $outputDir -Force

$exitCode = Invoke-Pipeline $imagesPath $outputDir

$summaryPath = Join-Path $outputDir 'run-summary.json'
if (-not (Test-Path -LiteralPath $summaryPath)) {
  throw 'Expected run-summary.json after the pipeline rejects an empty JPG folder.'
}
if ($exitCode -eq 0) {
  throw 'Expected a nonzero exit code for an input folder without JPG files.'
}

$summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
if ($summary.status -ne 'failed' -or $summary.inputPhotoCount -ne 0) {
  throw 'Expected a failed summary with inputPhotoCount equal to zero.'
}
if (Test-Path -LiteralPath (Join-Path $outputDir 'dense/fused.ply')) {
  throw 'An invalid input must not produce a fused point cloud.'
}
if (-not (Test-Path -LiteralPath (Join-Path $outputDir 'process-drone.log'))) {
  throw 'Expected a local diagnostic log for the failed run.'
}

Write-Host 'PASS: empty JPG input fails with a truthful summary and no fused cloud.'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$junctionPath = Join-Path $testRoot 'repo-junction'
$junctionOutput = Join-Path $testRoot 'junction-output'
$junctionCreated = $false
try {
  $null = New-Item -ItemType Junction -Path $junctionPath -Target $repoRoot -ErrorAction Stop
  $junctionCreated = $true
} catch {
  Write-Host "SKIP: junction rejection check unavailable ($($_.Exception.Message))."
}
if ($junctionCreated) {
  $null = New-Item -ItemType Directory -Path $junctionOutput -Force
  $junctionExitCode = Invoke-Pipeline (Join-Path $junctionPath 'images') $junctionOutput
  if ($junctionExitCode -eq 0) { throw 'Expected ImagesPath through a repository junction to fail.' }
  Write-Host 'PASS: repository junction paths are rejected before processing.'
}

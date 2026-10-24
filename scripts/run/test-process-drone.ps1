$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('mmsp-process-drone-' + [guid]::NewGuid().ToString('N'))
$portableRoot = Join-Path ([IO.Path]::GetTempPath()) ('mmsp-portable-runner-' + [guid]::NewGuid().ToString('N'))
$imagesPath = Join-Path $testRoot 'images'
$emptyImagesPath = Join-Path $testRoot 'empty-images'
$outputDir = Join-Path $testRoot 'output'
$scriptPath = Join-Path $PSScriptRoot 'process-drone.ps1'
$fakeColmapPath = Join-Path $testRoot 'fake-colmap.cmd'
$fakeArgsPath = Join-Path $testRoot 'fake-colmap-args.txt'
$gpuIndexPath = Join-Path $testRoot 'fake-colmap-gpu-index.txt'

function Invoke-Pipeline {
  param(
    [string]$InputPath,
    [string]$TargetOutput,
    [string]$ColmapPath,
    [string]$GpuIndex,
    [string]$FailStage,
    [string]$RunnerPath,
    [string]$ValidationFailure,
    [switch]$ClearCudaHome,
    [switch]$EmitStderr,
    [switch]$NativeGpuSift
  )

  if (-not $RunnerPath) { $RunnerPath = $scriptPath }
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $arguments = @('-NoProfile', '-File', $RunnerPath, '-ImagesPath', $InputPath, '-OutputDir', $TargetOutput)
  if ($ColmapPath) { $arguments += @('-ColmapExe', $ColmapPath) }
  if (-not [string]::IsNullOrEmpty($GpuIndex)) { $arguments += @('-GpuIndex', $GpuIndex) }
  if ($NativeGpuSift) { $arguments += '-NativeGpuSift' }
  $startInfo.Arguments = (@($arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' ')
  if ($ClearCudaHome) {
    [void]$startInfo.EnvironmentVariables.Remove('MMSP_CUDA_HOME')
  } else {
    $startInfo.EnvironmentVariables['MMSP_CUDA_HOME'] = $testRoot
  }
  $startInfo.EnvironmentVariables['PATH'] = Join-Path $testRoot 'empty-path'
  if ($FailStage) { $startInfo.EnvironmentVariables['MMSP_FAKE_FAIL_STAGE'] = $FailStage }
  if ($ValidationFailure) { $startInfo.EnvironmentVariables['MMSP_FAKE_VALIDATION_FAILURE'] = $ValidationFailure }
  if ($EmitStderr) { $startInfo.EnvironmentVariables['MMSP_FAKE_STDERR'] = '1' }
  if ($ColmapPath) {
    $startInfo.EnvironmentVariables['MMSP_FAKE_ARGS_PATH'] = $fakeArgsPath
    $startInfo.EnvironmentVariables['MMSP_FAKE_GPU_INDEX_PATH'] = $gpuIndexPath
  }
  $process = [Diagnostics.Process]::Start($startInfo)
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  return [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

function Get-StageEvents([string]$Output) {
  $prefix = 'MMSP_STAGE_EVENT '
  $lines = @($Output -split "`r?`n" | Where-Object { $_.StartsWith($prefix, [StringComparison]::Ordinal) })
  return @($lines | ForEach-Object { $_.Substring($prefix.Length) | ConvertFrom-Json })
}

function Read-Summary([string]$TargetOutput) {
  $path = Join-Path $TargetOutput 'run-summary.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Expected run-summary.json.' }
  return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

$null = New-Item -ItemType Directory -Path $emptyImagesPath -Force
$null = New-Item -ItemType Directory -Path $outputDir -Force
$emptyResult = Invoke-Pipeline $emptyImagesPath $outputDir $null $null $null
if (-not (Test-Path -LiteralPath (Join-Path $outputDir 'run-summary.json') -PathType Leaf)) {
  throw 'Expected run-summary.json after the pipeline rejects an empty JPG folder.'
}
if ($emptyResult.ExitCode -eq 0) { throw 'Expected empty JPG input to return a nonzero exit code.' }
$emptySummary = Read-Summary $outputDir
if ($emptySummary.status -ne 'failed' -or $emptySummary.inputPhotoCount -ne 0 -or $emptySummary.exitCode -eq 0) {
  throw 'Expected a failed summary with inputPhotoCount equal to zero and a nonzero exitCode.'
}
if (Test-Path -LiteralPath (Join-Path $outputDir 'dense/fused.ply')) {
  throw 'An invalid input must not produce a fused point cloud.'
}
if (-not (Test-Path -LiteralPath (Join-Path $outputDir 'process-drone.log'))) {
  throw 'Expected a local diagnostic log for the failed run.'
}
Write-Host 'PASS: empty JPG input fails with a truthful summary and no fused cloud.'

$missingImagesPath = Join-Path $testRoot 'missing-images'
$missingImagesOutput = Join-Path $testRoot 'missing-images-output'
$missingImages = Invoke-Pipeline $missingImagesPath $missingImagesOutput $null $null $null
if ($missingImages.ExitCode -eq 0) { throw 'Expected a missing ImagesPath to return a nonzero exit code.' }
$missingImagesSummary = Read-Summary $missingImagesOutput
if ($missingImagesSummary.schemaVersion -ne 1 -or $missingImagesSummary.status -ne 'failed' -or
    $missingImagesSummary.exitCode -eq 0 -or -not $missingImagesSummary.error) {
  throw 'Expected a versioned failed summary when ImagesPath does not exist.'
}
Write-Host 'PASS: missing ImagesPath fails with a versioned summary and nonzero exit code.'

$null = New-Item -ItemType Directory -Path $imagesPath -Force
[IO.File]::WriteAllBytes((Join-Path $imagesPath 'photo-1.jpg'), [byte[]](1, 2, 3, 4))
[IO.File]::WriteAllBytes((Join-Path $imagesPath 'photo-2.jpg'), [byte[]](5, 6, 7, 8))
$fakeColmapScript = @'
$ErrorActionPreference = 'Stop'
$colmapArgs = [string[]]$args
$stage = $colmapArgs[0]
for ($i = 0; $i -lt ($colmapArgs.Length - 1); $i++) {
  if ($colmapArgs[$i] -eq '--output_path') { $outputPath = $colmapArgs[$i + 1] }
  if ($colmapArgs[$i] -eq '--workspace_path') { $workspacePath = $colmapArgs[$i + 1] }
  if ($colmapArgs[$i] -eq '--PatchMatchStereo.gpu_index') { $gpuIndex = $colmapArgs[$i + 1] }
}
if ($env:MMSP_FAKE_ARGS_PATH) {
  [IO.File]::AppendAllText($env:MMSP_FAKE_ARGS_PATH, ($stage + "`t" + ($colmapArgs -join "`t") + [Environment]::NewLine))
}
if ($stage -eq 'patch_match_stereo' -and $env:MMSP_FAKE_GPU_INDEX_PATH) {
  [IO.File]::WriteAllText($env:MMSP_FAKE_GPU_INDEX_PATH, $gpuIndex)
}
if ($env:MMSP_FAKE_FAIL_STAGE -eq $stage) { exit 7 }
switch ($stage) {
  'mapper' {
    $modelPath = Join-Path $outputPath '0'
    $null = New-Item -ItemType Directory -Path $modelPath -Force
    if ($env:MMSP_FAKE_VALIDATION_FAILURE -ne 'missing_mapper_model') {
      [IO.File]::WriteAllBytes((Join-Path $modelPath 'cameras.bin'), [byte[]](0))
    }
  }
  'model_analyzer' {
    if ($env:MMSP_FAKE_VALIDATION_FAILURE -ne 'missing_registration_count') {
      Write-Output 'Registered images: 2'
    }
  }
  'image_undistorter' {
    $stereoPath = Join-Path $outputPath 'stereo'
    $null = New-Item -ItemType Directory -Path $stereoPath -Force
    if ($env:MMSP_FAKE_VALIDATION_FAILURE -ne 'missing_patch_match_config') {
      [IO.File]::WriteAllText((Join-Path $stereoPath 'patch-match.cfg'), "__auto__, 2`nphoto-1.jpg`nphoto-2.jpg`n")
    }
  }
  'patch_match_stereo' {
    if ($env:MMSP_FAKE_VALIDATION_FAILURE -ne 'missing_depth_map') {
      $depthPath = Join-Path $workspacePath 'stereo/depth_maps'
      $null = New-Item -ItemType Directory -Path $depthPath -Force
      [IO.File]::WriteAllBytes((Join-Path $depthPath 'photo-1.jpg.bin'), [byte[]](0))
    }
  }
  'stereo_fusion' {
    $header = "ply`nformat binary_little_endian 1.0`nelement vertex 1`nproperty float x`nproperty float y`nproperty float z`nend_header`n"
    $stream = [IO.File]::Open((Join-Path (Split-Path $outputPath -Parent) 'fused.ply'), [IO.FileMode]::Create)
    try {
      $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
      $stream.Write($headerBytes, 0, $headerBytes.Length)
      foreach ($coordinate in @(1.0, 2.0, 3.0)) {
        $coordinateBytes = [BitConverter]::GetBytes([single]$coordinate)
        $stream.Write($coordinateBytes, 0, $coordinateBytes.Length)
      }
    } finally { $stream.Dispose() }
    Write-Output 'Number of fused points: 1'
  }
}
exit 0
'@
[IO.File]::WriteAllText((Join-Path $testRoot 'fake-colmap.ps1'), $fakeColmapScript, [Text.UTF8Encoding]::new($false))
$powerShellExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$fakeColmapCmd = "@echo off`r`n`"$powerShellExe`" -NoProfile -ExecutionPolicy Bypass -File `"%~dp0fake-colmap.ps1`" %*`r`nexit /b %errorlevel%`r`n"
$fakeColmapCmd = $fakeColmapCmd.Replace('@echo off', "@echo off`r`nif `"%MMSP_FAKE_STDERR%`"==`"1`" echo fake COLMAP log on stderr 1>&2")
[IO.File]::WriteAllText($fakeColmapPath, $fakeColmapCmd, [Text.Encoding]::ASCII)
$portableRunDir = Join-Path $portableRoot 'scripts/run'
$null = New-Item -ItemType Directory -Path $portableRunDir -Force
Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $portableRunDir 'process-drone.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../env.ps1') -Destination (Join-Path $portableRoot 'scripts/env.ps1')

$successOutput = Join-Path $testRoot 'success-output'
$success = Invoke-Pipeline $imagesPath $successOutput $fakeColmapPath '3' $null (Join-Path $portableRunDir 'process-drone.ps1') -ClearCudaHome
if ($success.ExitCode -ne 0) {
  $preChangeSummary = Read-Summary $successOutput
  if ($preChangeSummary.error -match 'CudaEnv is not set') {
    throw 'Explicit -ColmapExe incorrectly requires MMSP_CUDA_HOME or env.local.ps1.'
  }
  throw 'Expected the fake COLMAP pipeline to complete successfully without MMSP_CUDA_HOME.'
}
$summary = Read-Summary $successOutput
$summaryFields = @(
  'status', 'inputPhotoCount', 'registeredPhotoCount', 'fusedPointCount', 'depthMapCount', 'inputUnchanged',
  'stageTimingsSeconds', 'totalSeconds', 'peakVramMb', 'vramSampleCount', 'startedAtUtc', 'completedAtUtc', 'error', 'exitCode'
)
foreach ($field in $summaryFields) {
  if ($summary.PSObject.Properties.Name -notcontains $field) { throw "Run summary is missing existing field '$field'." }
}
if ($summary.schemaVersion -ne 1 -or $summary.status -ne 'success' -or $summary.exitCode -ne 0) {
  throw 'Expected a successful run summary with schema version 1 and exitCode 0.'
}
if ($summary.fusedCloudPath -ne 'dense/fused.ply') { throw 'Expected fusedCloudPath relative to OutputDir.' }
if ($summary.inputUnchanged -ne $true -or $summary.fusedPointCount -ne 1 -or $summary.depthMapCount -ne 1) {
  throw 'Expected the successful fake run to preserve inputs and report its fused output.'
}
$successEvents = @(Get-StageEvents $success.StdOut)
if ($successEvents.Count -ne 14) { throw 'Expected started and completed machine-readable events for all seven COLMAP stages.' }
foreach ($event in $successEvents) {
  if ($event.schemaVersion -ne 1 -or -not $event.stage -or $event.status -notin @('started', 'completed')) {
    throw 'A successful stage event had an invalid JSON schema.'
  }
}
if (-not (Test-Path -LiteralPath (Join-Path $successOutput $summary.fusedCloudPath) -PathType Leaf)) {
  throw 'The relative fused-cloud path did not resolve under OutputDir.'
}
$patchArguments = @(Get-Content -LiteralPath $fakeArgsPath | Where-Object { $_.StartsWith("patch_match_stereo`t", [StringComparison]::Ordinal) })
if ($patchArguments.Count -ne 1 -or $patchArguments[0] -notmatch '--PatchMatchStereo.gpu_index	3(?:	|$)') {
  throw 'Expected the selected GPU index to reach PatchMatch.'
}
if ((Get-Content -LiteralPath $gpuIndexPath -Raw) -ne '3') { throw 'The fake COLMAP executable was not selected.' }
$cpuExtractArguments = @(Get-Content -LiteralPath $fakeArgsPath | Where-Object { $_.StartsWith("feature_extractor`t", [StringComparison]::Ordinal) })
if ($cpuExtractArguments.Count -ne 1 -or $cpuExtractArguments[0] -match '--SiftExtraction.use_gpu_native') {
  throw 'The default runner must keep native CUDA SIFT extraction disabled.'
}
Write-Host 'PASS: fake COLMAP success reports valid summary JSON, stage events, output path, and selected GPU.'

$nativeGpuOutput = Join-Path $testRoot 'native-gpu-output'
$nativeGpu = Invoke-Pipeline $imagesPath $nativeGpuOutput $fakeColmapPath '0' $null $null $null -NativeGpuSift
if ($nativeGpu.ExitCode -ne 0 -or (Read-Summary $nativeGpuOutput).status -ne 'success') {
  throw 'The opt-in native CUDA SIFT run must complete with the fake COLMAP pipeline.'
}
$nativeGpuExtractArguments = @(Get-Content -LiteralPath $fakeArgsPath | Where-Object { $_.StartsWith("feature_extractor`t", [StringComparison]::Ordinal) } | Select-Object -Last 1)
if ($nativeGpuExtractArguments.Count -ne 1 -or
    $nativeGpuExtractArguments[0] -notmatch '--FeatureExtraction.use_gpu\t0(?:\t|$)' -or
    $nativeGpuExtractArguments[0] -notmatch '--SiftExtraction.use_gpu_native\t1(?:\t|$)') {
  throw 'The native CUDA SIFT opt-in must keep COLMAP GPU mode off and enable only the existing native SIFT extractor.'
}
Write-Host 'PASS: native CUDA SIFT is off by default and opt-in passes the existing extractor flag with CUDA SIFT defaults preserved.'

$stderrOutput = Join-Path $testRoot 'stderr-success-output'
$stderrSuccess = Invoke-Pipeline $imagesPath $stderrOutput $fakeColmapPath '0' $null $null $null -EmitStderr
if ($stderrSuccess.ExitCode -ne 0 -or (Read-Summary $stderrOutput).status -ne 'success') {
  throw 'A zero-exit COLMAP process that writes logs to stderr must be treated as successful.'
}
Write-Host 'PASS: successful COLMAP stderr output does not turn a stage into a failure.'

$failureOutput = Join-Path $testRoot 'failure-output'
$failure = Invoke-Pipeline $imagesPath $failureOutput $fakeColmapPath '2' 'patch_match_stereo'
if ($failure.ExitCode -ne 7) { throw 'Expected a COLMAP stage failure to preserve its nonzero exit code.' }
$failureSummary = Read-Summary $failureOutput
if ($failureSummary.status -ne 'failed' -or $failureSummary.exitCode -ne 7 -or $failureSummary.error -eq $null) {
  throw 'Expected a failed summary with the COLMAP exit code and error.'
}
$failureEvents = @(Get-StageEvents $failure.StdOut)
$failedPatchEvent = @($failureEvents | Where-Object { $_.stage -eq 'patch_match_stereo' -and $_.status -eq 'failed' })
if ($failedPatchEvent.Count -ne 1 -or $failedPatchEvent[0].exitCode -ne 7) {
  throw 'Expected a parseable failed stage event with the COLMAP exit code.'
}
if (Test-Path -LiteralPath (Join-Path $failureOutput 'dense/fused.ply')) {
  throw 'A failed COLMAP stage must not report a fused cloud.'
}
Write-Host 'PASS: COLMAP nonzero failure produces a failed summary, failed event, and matching process exit code.'

$validationMapperOutput = Join-Path $testRoot 'validation-mapper-output'
$validationMapper = Invoke-Pipeline $imagesPath $validationMapperOutput $fakeColmapPath '0' $null $null -ValidationFailure 'missing_mapper_model'
if ($validationMapper.ExitCode -eq 0) { throw 'Expected mapper output validation to fail the pipeline.' }
$validationMapperEvents = @(Get-StageEvents $validationMapper.StdOut | Where-Object { $_.stage -eq 'mapper' })
if ($validationMapperEvents.Count -ne 2 -or $validationMapperEvents[0].status -ne 'started' -or
    $validationMapperEvents[1].status -ne 'failed' -or $validationMapperEvents[1].exitCode -eq 0) {
  throw 'Expected mapper output validation to emit started and failed events, with no completed event.'
}
Write-Host 'PASS: successful COLMAP invocation followed by mapper validation failure emits a failed stage event.'

$validationDepthOutput = Join-Path $testRoot 'validation-depth-output'
$validationDepth = Invoke-Pipeline $imagesPath $validationDepthOutput $fakeColmapPath '0' $null $null -ValidationFailure 'missing_depth_map'
if ($validationDepth.ExitCode -eq 0) { throw 'Expected PatchMatch output validation to fail the pipeline.' }
$validationPatchEvents = @(Get-StageEvents $validationDepth.StdOut | Where-Object { $_.stage -eq 'patch_match_stereo' })
if ($validationPatchEvents.Count -ne 2 -or $validationPatchEvents[0].status -ne 'started' -or
    $validationPatchEvents[1].status -ne 'failed' -or $validationPatchEvents[1].exitCode -eq 0) {
  throw 'Expected depth-map validation to emit started and failed events, with no completed event.'
}
Write-Host 'PASS: successful PatchMatch invocation followed by depth validation failure emits a failed stage event.'

$missingExeOutput = Join-Path $testRoot 'missing-exe-output'
$missingExe = Invoke-Pipeline $imagesPath $missingExeOutput (Join-Path $testRoot 'missing-colmap.exe') $null $null
if ($missingExe.ExitCode -eq 0 -or (Read-Summary $missingExeOutput).status -ne 'failed') {
  throw 'Expected a missing COLMAP executable to be rejected.'
}
$negativeGpu = Invoke-Pipeline $imagesPath (Join-Path $testRoot 'negative-gpu-output') $fakeColmapPath '-1' $null
if ($negativeGpu.ExitCode -eq 0) { throw 'Expected a negative GPU index to be rejected.' }
Write-Host 'PASS: missing executable and negative GPU index are rejected.'

$nonEmptyOutput = Join-Path $testRoot 'nonempty-output'
$null = New-Item -ItemType Directory -Path $nonEmptyOutput -Force
$markerPath = Join-Path $nonEmptyOutput 'preserve-me.txt'
[IO.File]::WriteAllText($markerPath, 'original')
$overwrite = Invoke-Pipeline $imagesPath $nonEmptyOutput $fakeColmapPath $null $null
if ($overwrite.ExitCode -eq 0 -or (Get-Content -LiteralPath $markerPath -Raw) -ne 'original') {
  throw 'A nonempty output directory must be rejected without overwriting existing files.'
}
Write-Host 'PASS: nonempty output directories are rejected without overwriting their contents.'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$junctionPath = Join-Path $testRoot 'repo-junction'
$junctionOutput = Join-Path $testRoot 'junction-output'
$junctionCreated = $false
try {
  $null = New-Item -ItemType Junction -Path $junctionPath -Target $repoRoot -ErrorAction Stop
  $junctionCreated = $true
} catch {
  Write-Host 'SKIP: junction rejection check unavailable.'
}
if ($junctionCreated) {
  $null = New-Item -ItemType Directory -Path $junctionOutput -Force
  $junctionResult = Invoke-Pipeline (Join-Path $junctionPath 'images') $junctionOutput $null $null $null
  if ($junctionResult.ExitCode -eq 0) { throw 'Expected ImagesPath through a repository junction to fail.' }
  Write-Host 'PASS: repository junction paths are rejected before processing.'
}

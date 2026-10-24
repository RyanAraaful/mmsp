[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ImagesPath,
  [Parameter(Mandatory = $true)][string]$OutputDir,
  [string]$ColmapExe,
  [ValidateRange(0, 2147483647)][int]$GpuIndex = 0,
  [switch]$NativeGpuSift
)

$ErrorActionPreference = 'Stop'
$requestedColmapExe = $ColmapExe
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$processLogPath = $null
$processLogWriter = $null
$summaryPath = $null
$vramSamplesPath = $null
$samplerJob = $null
$colmapExe = $null
$scriptExitCode = 1
$runTimer = [Diagnostics.Stopwatch]::StartNew()
$stageTimings = [ordered]@{}
$registeredLogCount = $null
$fusedLogPointCount = $null
$pendingStage = $null
$summary = [ordered]@{
  schemaVersion = 1
  status = 'failed'
  inputPhotoCount = $null
  registeredPhotoCount = $null
  fusedPointCount = $null
  depthMapCount = $null
  inputUnchanged = $null
  stageTimingsSeconds = $stageTimings
  totalSeconds = $null
  peakVramMb = $null
  vramSampleCount = 0
  startedAtUtc = [DateTime]::UtcNow.ToString('o')
  completedAtUtc = $null
  error = $null
  exitCode = 1
  fusedCloudPath = 'dense/fused.ply'
}

function Test-PathWithin([string]$Path, [string]$ParentPath) {
  $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $fullParent = [IO.Path]::GetFullPath($ParentPath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $fullPath.Equals($fullParent, [StringComparison]::OrdinalIgnoreCase) -or
    $fullPath.StartsWith($fullParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparsePointInPath([string]$Path, [string]$Label) {
  $fullPath = [IO.Path]::GetFullPath($Path)
  $root = [IO.Path]::GetPathRoot($fullPath)
  $current = $root
  foreach ($component in ($fullPath.Substring($root.Length) -split '[\\/]')) {
    if ([string]::IsNullOrWhiteSpace($component)) { continue }
    $current = Join-Path $current $component
    if (Test-Path -LiteralPath $current) {
      $attributes = [IO.File]::GetAttributes($current)
      if (([int]$attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label cannot pass through a symbolic link or junction: $current"
      }
    }
  }
}

function Write-RunLog([string]$Message) {
  if ($script:processLogWriter) {
    $script:processLogWriter.WriteLine(('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffK'), $Message))
    $script:processLogWriter.Flush()
  }
}

function Write-StageEvent {
  param(
    [string]$Name,
    [string]$Status,
    [object]$ExitCode = $null,
    [object]$DurationSeconds = $null
  )
  $event = [ordered]@{
    schemaVersion = 1
    stage = $Name
    status = $Status
    timestampUtc = [DateTime]::UtcNow.ToString('o')
  }
  if ($null -ne $ExitCode) { $event.exitCode = $ExitCode }
  if ($null -ne $DurationSeconds) { $event.durationSeconds = $DurationSeconds }
  Write-Host ('MMSP_STAGE_EVENT ' + ($event | ConvertTo-Json -Compress -Depth 3))
}

function Complete-ColmapStage([string]$Name) {
  $stage = $script:pendingStage
  if ($null -eq $stage -or $stage.Name -ne $Name) { throw "Cannot complete COLMAP stage '$Name' without a matching successful invocation." }
  Write-StageEvent $Name 'completed' $stage.ExitCode $stage.DurationSeconds
  $script:pendingStage = $null
}

function Invoke-ColmapStage([string]$Name, [string[]]$Arguments) {
  $timer = [Diagnostics.Stopwatch]::StartNew()
  $allArguments = @($Name, '--log_target', 'stderr', '--log_color', '0') + $Arguments
  $nativeExitCode = $null
  Write-RunLog ("START {0}: colmap {1}" -f $Name, ($allArguments -join ' '))
  Write-StageEvent $Name 'started'
  try {
    $previousErrorActionPreference = $ErrorActionPreference
    try {
      # Windows PowerShell 5.1 surfaces native stderr writes as ErrorRecords.
      # COLMAP writes normal progress logs to stderr, so they must not abort a
      # zero-exit stage while ErrorActionPreference is Stop for script errors.
      $ErrorActionPreference = 'Continue'
      & $script:colmapExe @allArguments 2>&1 | ForEach-Object {
        $line = [string]$_
        $script:processLogWriter.WriteLine($line)
        if ($Name -eq 'model_analyzer' -and $line -match 'Registered images:\s*(\d+)') {
          $script:registeredLogCount = [int]$Matches[1]
        }
        if ($Name -eq 'stereo_fusion' -and $line -match 'Number of fused points:\s*([\d,]+)') {
          $script:fusedLogPointCount = [long](($Matches[1] -replace ',', ''))
        }
        Write-Host $line
      }
      $nativeExitCode = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($nativeExitCode -ne 0) { throw "COLMAP returned exit code $nativeExitCode." }
  } catch {
    $timer.Stop()
    if ($script:processLogWriter) { $script:processLogWriter.Flush() }
    $script:stageTimings[$Name] = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
    Write-RunLog ("END {0}: {1:F3}s" -f $Name, $timer.Elapsed.TotalSeconds)
    $script:scriptExitCode = if ($null -ne $nativeExitCode -and $nativeExitCode -ne 0) { $nativeExitCode } else { 1 }
    $script:pendingStage = $null
    Write-StageEvent $Name 'failed' $script:scriptExitCode $script:stageTimings[$Name]
    throw "$Name failed with COLMAP exit code $script:scriptExitCode. See process-drone.log."
  }
  $timer.Stop()
  if ($script:processLogWriter) { $script:processLogWriter.Flush() }
  $script:stageTimings[$Name] = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
  Write-RunLog ("END {0}: {1:F3}s" -f $Name, $timer.Elapsed.TotalSeconds)
  $script:pendingStage = [pscustomobject]@{
    Name = $Name
    ExitCode = $nativeExitCode
    DurationSeconds = $script:stageTimings[$Name]
  }
}

function Get-PlyVertexInfo([string]$Path) {
  $stream = [IO.File]::OpenRead($Path)
  try {
    $header = [Collections.Generic.List[string]]::new()
    $headerEnded = $false
    while ($stream.Position -lt $stream.Length -and $header.Count -lt 256) {
      $lineBytes = [Collections.Generic.List[byte]]::new()
      $terminated = $false
      while ($stream.Position -lt $stream.Length) {
        $value = $stream.ReadByte()
        if ($value -eq 10) { $terminated = $true; break }
        if ($value -ne 13) { $lineBytes.Add([byte]$value) }
        if ($lineBytes.Count -gt 4096) { throw 'PLY header line is too long.' }
      }
      $line = [Text.Encoding]::ASCII.GetString($lineBytes.ToArray())
      $header.Add($line)
      if ($line -eq 'end_header') {
        if (-not $terminated) { throw 'PLY end_header line is not terminated.' }
        $headerEnded = $true
        break
      }
    }
    if (-not $headerEnded -or $header[0] -ne 'ply') { throw 'Fused output has no valid PLY header.' }

    $format = $null
    $vertexCount = $null
    $vertexBytes = 0L
    $inVertices = $false
    $coordinates = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $typeSizes = @{
      char = 1; int8 = 1; uchar = 1; uint8 = 1
      short = 2; int16 = 2; ushort = 2; uint16 = 2
      int = 4; int32 = 4; uint = 4; uint32 = 4; float = 4; float32 = 4
      double = 8; float64 = 8
    }
    foreach ($line in $header) {
      if ($line -match '^format\s+(\S+)\s+') { $format = $Matches[1] }
      if ($line -match '^element\s+(\S+)\s+(\d+)\s*$') {
        $inVertices = $Matches[1] -eq 'vertex'
        if ($inVertices) { $vertexCount = [long]::Parse($Matches[2]) }
        continue
      }
      if ($inVertices -and $line -match '^property\s+(\S+)\s+(\S+)\s*$') {
        $type = $Matches[1].ToLowerInvariant()
        $property = $Matches[2]
        if (-not $typeSizes.ContainsKey($type)) { throw "Unsupported PLY vertex property type '$type'." }
        $vertexBytes += [long]$typeSizes[$type]
        if ($property -in @('x', 'y', 'z')) { [void]$coordinates.Add($property) }
      } elseif ($inVertices -and $line -match '^property\s+list\b') {
        throw 'PLY vertex list properties are not supported.'
      }
    }
    if ($format -ne 'binary_little_endian' -or $null -eq $vertexCount -or $vertexCount -le 0) {
      throw 'Fused output must be a binary little-endian PLY with at least one vertex.'
    }
    if ($coordinates.Count -ne 3 -or $vertexBytes -lt 12) { throw 'PLY vertices do not declare readable x, y, and z coordinates.' }
    $payloadBytes = $stream.Length - $stream.Position
    if ($payloadBytes -lt ($vertexCount * $vertexBytes)) { throw 'PLY vertex payload is truncated.' }
    return [pscustomobject]@{ VertexCount = $vertexCount; VertexBytes = $vertexBytes; PayloadBytes = $payloadBytes }
  } finally {
    $stream.Dispose()
  }
}

try {
  $imagesFullPath = [IO.Path]::GetFullPath($ImagesPath)
  $outputFullPath = [IO.Path]::GetFullPath($OutputDir)
  Assert-NoReparsePointInPath $imagesFullPath 'ImagesPath'
  Assert-NoReparsePointInPath $outputFullPath 'OutputDir'
  if (Test-PathWithin $outputFullPath $repoRoot) { throw 'OutputDir must be outside the Git repository.' }
  if (Test-PathWithin $outputFullPath $imagesFullPath) { throw 'OutputDir must not be the image folder or a child of it.' }

  if (Test-Path -LiteralPath $outputFullPath) {
    if (@(Get-ChildItem -LiteralPath $outputFullPath -Force).Count -gt 0) {
      throw 'OutputDir must be empty; choose a new folder to preserve existing files.'
    }
  } else {
    $null = New-Item -ItemType Directory -Path $outputFullPath -Force
  }
  $processLogPath = Join-Path $outputFullPath 'process-drone.log'
  $summaryPath = Join-Path $outputFullPath 'run-summary.json'
  $vramSamplesPath = Join-Path $outputFullPath 'gpu-memory-mb.csv'
  $processLogWriter = [IO.StreamWriter]::new($processLogPath, $false, [Text.UTF8Encoding]::new($false))

  if (Test-PathWithin $imagesFullPath $repoRoot) { throw 'ImagesPath must be outside the Git repository.' }
  if (-not (Test-Path -LiteralPath $imagesFullPath -PathType Container)) { throw 'ImagesPath does not exist or is not a folder.' }
  $inputEntries = @(Get-ChildItem -LiteralPath $imagesFullPath -Force -Recurse)
  $linkedEntry = $inputEntries | Where-Object { ([int]$_.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0 } | Select-Object -First 1
  if ($linkedEntry) { throw "ImagesPath contains a symbolic link or junction: $($linkedEntry.FullName)" }
  $imageFiles = @($inputEntries | Where-Object { -not $_.PSIsContainer -and $_.Extension -match '^\.(jpg|jpeg)$' })
  $summary.inputPhotoCount = $imageFiles.Count
  Write-RunLog "Input JPG/JPEG files: $($imageFiles.Count)"
  if ($imageFiles.Count -eq 0) { throw 'ImagesPath contains no JPG or JPEG files.' }

  $snapshotTimer = [Diagnostics.Stopwatch]::StartNew()
  $inputHashes = @{}
  foreach ($image in $imageFiles) {
    $inputHashes[$image.FullName] = (Get-FileHash -LiteralPath $image.FullName -Algorithm SHA256).Hash
  }
  $snapshotTimer.Stop()
  $stageTimings['input_snapshot'] = [Math]::Round($snapshotTimer.Elapsed.TotalSeconds, 3)

  $imageRootPrefix = $imagesFullPath
  if (-not $imageRootPrefix.EndsWith('\') -and -not $imageRootPrefix.EndsWith('/')) {
    $imageRootPrefix += [IO.Path]::DirectorySeparatorChar
  }
  $imageListPath = Join-Path $outputFullPath 'input-images.txt'
  $imageList = @($imageFiles | ForEach-Object {
    $_.FullName.Substring($imageRootPrefix.Length).TrimStart('\', '/') -replace '\\', '/'
  })
  [IO.File]::WriteAllLines($imageListPath, [string[]]$imageList, [Text.UTF8Encoding]::new($false))
  Write-RunLog "Wrote COLMAP image list with $($imageList.Count) JPG/JPEG files."

  if ([string]::IsNullOrWhiteSpace($requestedColmapExe)) {
    . (Join-Path $PSScriptRoot '../env.ps1')
    $colmapExe = $ColmapExe
  } else {
    $colmapExe = $requestedColmapExe
  }
  if (-not (Test-Path -LiteralPath $colmapExe -PathType Leaf)) { throw 'Selected COLMAP executable was not found.' }
  Write-RunLog "COLMAP executable: $colmapExe"

  $databasePath = Join-Path $outputFullPath 'database.db'
  $sparsePath = Join-Path $outputFullPath 'sparse'
  $sparseModelPath = Join-Path $sparsePath '0'
  $densePath = Join-Path $outputFullPath 'dense'
  $fusedPath = Join-Path $densePath 'fused.ply'
  $gpu = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
  if ($gpu) {
    try {
      $nvidiaSmiPath = $gpu.Source
      $samplerJob = Start-Job -ArgumentList $nvidiaSmiPath, $vramSamplesPath, $GpuIndex -ScriptBlock {
        param($NvidiaSmiPath, $SamplePath, $SampleGpuIndex)
        while ($true) {
          try {
            $sample = & $NvidiaSmiPath --query-gpu=memory.used "--id=$SampleGpuIndex" --format=csv,noheader,nounits 2>$null
            if ($LASTEXITCODE -eq 0 -and $sample -match '^\s*(\d+)') {
              [IO.File]::AppendAllText($SamplePath, $Matches[1] + [Environment]::NewLine)
            }
          } catch { }
          Start-Sleep -Seconds 1
        }
      }
      Write-RunLog "Started one-second GPU $GpuIndex memory sampler."
    } catch {
      $samplerJob = $null
      Write-RunLog "GPU memory sampling unavailable: $($_.Exception.Message)"
    }
  }

  $featureExtractionArguments = @('--database_path', $databasePath, '--image_path', $imagesFullPath,
    '--image_list_path', $imageListPath,
    '--ImageReader.single_camera', '1', '--FeatureExtraction.use_gpu', '0', '--FeatureExtraction.max_image_size', '2048',
    '--SiftExtraction.max_num_features', '5000', '--FeatureExtraction.num_threads', '-1')
  if ($NativeGpuSift) { $featureExtractionArguments += @('--SiftExtraction.use_gpu_native', '1') }
  $null = Invoke-ColmapStage 'feature_extractor' $featureExtractionArguments
  Complete-ColmapStage 'feature_extractor'

  $null = Invoke-ColmapStage 'sequential_matcher' (@('--database_path', $databasePath, '--SequentialMatching.overlap', '10',
    '--SequentialMatching.quadratic_overlap', '1', '--FeatureMatching.use_gpu', '0', '--FeatureMatching.num_threads', '-1'))
  Complete-ColmapStage 'sequential_matcher'

  $null = New-Item -ItemType Directory -Path $sparsePath -Force
  $null = Invoke-ColmapStage 'mapper' @('--database_path', $databasePath, '--image_path', $imagesFullPath, '--output_path', $sparsePath,
    '--Mapper.image_list_path', $imageListPath)
  if (-not (Test-Path -LiteralPath (Join-Path $sparseModelPath 'cameras.bin') -PathType Leaf)) {
    throw 'Sparse mapper did not produce a model in sparse/0.'
  }
  Complete-ColmapStage 'mapper'

  $registeredLogCount = $null
  $null = Invoke-ColmapStage 'model_analyzer' @('--path', $sparseModelPath)
  if ($null -eq $registeredLogCount) { throw 'Could not read the registered photo count from model_analyzer.' }
  $summary.registeredPhotoCount = $registeredLogCount
  if ($summary.registeredPhotoCount -lt 2) { throw 'Sparse reconstruction registered fewer than two photos.' }
  Complete-ColmapStage 'model_analyzer'

  $null = Invoke-ColmapStage 'image_undistorter' (@('--image_path', $imagesFullPath, '--input_path', $sparseModelPath,
    '--output_path', $densePath, '--output_type', 'COLMAP', '--max_image_size', '700'))
  $patchConfigPath = Join-Path $densePath 'stereo/patch-match.cfg'
  if (-not (Test-Path -LiteralPath $patchConfigPath -PathType Leaf)) { throw 'Undistortion did not create stereo/patch-match.cfg.' }
  $patchConfig = [IO.File]::ReadAllText($patchConfigPath)
  $autoMatches = [regex]::Matches($patchConfig, '(?m)^__auto__,\s*\d+')
  if ($autoMatches.Count -eq 0) { throw 'PatchMatch config has no automatic source-view entries.' }
  $patchConfig = [regex]::Replace($patchConfig, '(?m)^(__auto__,\s*)\d+', '${1}8')
  [IO.File]::WriteAllText($patchConfigPath, $patchConfig, [Text.UTF8Encoding]::new($false))
  Complete-ColmapStage 'image_undistorter'

  $null = Invoke-ColmapStage 'patch_match_stereo' (@('--workspace_path', $densePath, '--workspace_format', 'COLMAP',
    '--PatchMatchStereo.max_image_size', '700', '--PatchMatchStereo.gpu_index', "$GpuIndex", '--PatchMatchStereo.window_radius', '3',
    '--PatchMatchStereo.window_step', '2', '--PatchMatchStereo.num_samples', '10', '--PatchMatchStereo.num_iterations', '1',
    '--PatchMatchStereo.min_triangulation_angle', '1.0', '--PatchMatchStereo.max_triangulation_angle', '65.0',
    '--PatchMatchStereo.geom_consistency', '1', '--PatchMatchStereo.geom_consistency_regularizer', '0.3',
    '--PatchMatchStereo.geom_consistency_max_cost', '3.0', '--PatchMatchStereo.filter', '1',
    '--PatchMatchStereo.filter_min_ncc', '0.15', '--PatchMatchStereo.filter_min_triangulation_angle', '3.0',
    '--PatchMatchStereo.filter_min_num_consistent', '2', '--PatchMatchStereo.filter_geom_consistency_max_cost', '1.0',
    '--PatchMatchStereo.pyramid_levels', '1', '--PatchMatchStereo.filter_min_confidence', '0.2',
    '--PatchMatchStereo.cache_size', '4'))
  $summary.depthMapCount = @(Get-ChildItem -LiteralPath (Join-Path $densePath 'stereo/depth_maps') -File -Filter '*.bin' -ErrorAction SilentlyContinue).Count
  if ($summary.depthMapCount -eq 0) { throw 'PatchMatch completed without writing depth maps.' }
  Complete-ColmapStage 'patch_match_stereo'

  $null = Invoke-ColmapStage 'stereo_fusion' (@('--workspace_path', $densePath, '--workspace_format', 'COLMAP', '--input_type', 'geometric',
    '--output_path', $fusedPath, '--StereoFusion.max_image_size', '700', '--StereoFusion.min_num_pixels', '3',
    '--StereoFusion.max_reproj_error', '4.0', '--StereoFusion.max_depth_error', '0.1', '--StereoFusion.max_normal_error', '20.0',
    '--StereoFusion.check_num_images', '30', '--StereoFusion.fuse_prior_weight', '1.0', '--StereoFusion.cache_size', '4'))
  if (-not (Test-Path -LiteralPath $fusedPath -PathType Leaf)) { throw 'Stereo fusion did not create dense/fused.ply.' }
  $logPointCount = $fusedLogPointCount
  if ($null -eq $logPointCount) { throw 'Could not read the fused point count from the fusion log.' }
  $plyInfo = Get-PlyVertexInfo $fusedPath
  if ($logPointCount -le 0 -or $logPointCount -ne $plyInfo.VertexCount) {
    throw 'Fusion log point count does not match the readable PLY vertex count.'
  }
  $summary.fusedPointCount = $plyInfo.VertexCount
  Complete-ColmapStage 'stereo_fusion'

  $integrityTimer = [Diagnostics.Stopwatch]::StartNew()
  $imagesAfter = @(Get-ChildItem -LiteralPath $imagesFullPath -File -Recurse | Where-Object { $_.Extension -match '^\.(jpg|jpeg)$' })
  if ($imagesAfter.Count -ne $inputHashes.Count) {
    $summary.inputUnchanged = $false
    throw 'Input JPG/JPEG file count changed during processing.'
  }
  foreach ($image in $imagesAfter) {
    if (-not $inputHashes.ContainsKey($image.FullName) -or
        (Get-FileHash -LiteralPath $image.FullName -Algorithm SHA256).Hash -ne $inputHashes[$image.FullName]) {
      $summary.inputUnchanged = $false
      throw 'An input JPG/JPEG changed during processing.'
    }
  }
  $integrityTimer.Stop()
  $stageTimings['input_integrity_check'] = [Math]::Round($integrityTimer.Elapsed.TotalSeconds, 3)
  $summary.inputUnchanged = $true

  $summary.status = 'success'
  $summary.error = $null
  $scriptExitCode = 0
  Write-RunLog "SUCCESS: $($summary.registeredPhotoCount) registered photos, $($summary.fusedPointCount) fused points."
} catch {
  $summary.status = 'failed'
  $summary.error = $_.Exception.Message
  if ($scriptExitCode -eq 0) { $scriptExitCode = 1 }
  if ($null -ne $script:pendingStage) {
    Write-StageEvent $script:pendingStage.Name 'failed' $scriptExitCode $script:pendingStage.DurationSeconds
    $script:pendingStage = $null
  }
  Write-RunLog "FAILED: $($summary.error)"
} finally {
  if ($samplerJob) {
    Stop-Job -Job $samplerJob -ErrorAction SilentlyContinue
    Remove-Job -Job $samplerJob -Force -ErrorAction SilentlyContinue
  }
  if ($vramSamplesPath -and (Test-Path -LiteralPath $vramSamplesPath -PathType Leaf)) {
    $samples = @(Get-Content -LiteralPath $vramSamplesPath | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    $summary.vramSampleCount = $samples.Count
    if ($samples.Count -gt 0) { $summary.peakVramMb = ($samples | Measure-Object -Maximum).Maximum }
  }
  $runTimer.Stop()
  $summary.totalSeconds = [Math]::Round($runTimer.Elapsed.TotalSeconds, 3)
  $summary.completedAtUtc = [DateTime]::UtcNow.ToString('o')
  $summary.exitCode = $scriptExitCode
  if ($summary.status -eq 'success' -and $scriptExitCode -ne 0) { $summary.status = 'failed' }
  if ($summaryPath -and (Test-Path -LiteralPath (Split-Path $summaryPath -Parent) -PathType Container)) {
    try {
      [IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    } catch {
      $scriptExitCode = 1
      Write-RunLog "FAILED to write run-summary.json: $($_.Exception.Message)"
    }
  }
  if ($processLogWriter) {
    try { $processLogWriter.Flush(); $processLogWriter.Dispose() } catch { }
  }
}

if ($scriptExitCode -eq 0) {
  Write-Host "Processing succeeded. Fused points: $($summary.fusedPointCount); wall time: $($summary.totalSeconds)s."
  exit 0
}
Write-Host "Processing failed (exit $scriptExitCode). See run-summary.json and process-drone.log when available." -ForegroundColor Red
exit $scriptExitCode

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$RuntimeDir,
  [ValidatePattern('^[A-Za-z0-9_-][A-Za-z0-9_.-]*$')][string]$BuildDirectory = 'build-mx150-final'
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$runtimePath = [IO.Path]::GetFullPath($RuntimeDir)
$runtimeDirectoryExists = Test-Path -LiteralPath $runtimePath

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

if (Test-PathWithin $runtimePath $repoRoot) { throw 'RuntimeDir must be outside the Git repository.' }
Assert-NoReparsePointInPath $runtimePath 'RuntimeDir'
if (Test-Path -LiteralPath $runtimePath) {
  if (-not (Test-Path -LiteralPath $runtimePath -PathType Container)) { throw 'RuntimeDir exists and is not a folder.' }
  if (Get-ChildItem -LiteralPath $runtimePath -Force | Select-Object -First 1) {
    throw 'RuntimeDir must be empty; choose a new folder to preserve existing files.'
  }
}

$buildDir = Join-Path $repoRoot "colmap/$BuildDirectory"
$exeDir = Join-Path $buildDir 'src/colmap/exe'
$colmapExe = Join-Path $exeDir 'colmap.exe'
$cachePath = Join-Path $buildDir 'CMakeCache.txt'
$runner = Join-Path $repoRoot 'scripts/run/process-drone.ps1'
$readme = Join-Path $repoRoot 'docs/runtime/README.md'

foreach ($requiredFile in @($colmapExe, $cachePath, $runner, $readme, (Join-Path $repoRoot 'LICENSE'), (Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md'))) {
  if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) { throw "Required runtime input is missing: $requiredFile" }
}

$cacheText = Get-Content -LiteralPath $cachePath -Raw
$sourceMatch = [regex]::Match($cacheText, '(?m)^CMAKE_HOME_DIRECTORY:[^=]*=(.+)$')
$sourceMatchesRepo = $false
if ($sourceMatch.Success) {
  $cacheSourcePath = [IO.Path]::GetFullPath($sourceMatch.Groups[1].Value.Trim()).TrimEnd('\')
  $repoSourcePath = [IO.Path]::GetFullPath((Join-Path $repoRoot 'colmap')).TrimEnd('\')
  $sourceMatchesRepo = $cacheSourcePath.Equals($repoSourcePath, [StringComparison]::OrdinalIgnoreCase)
}
if (-not $sourceMatchesRepo) {
  throw 'The selected build cache does not belong to this source checkout.'
}
$installedDirMatch = [regex]::Match($cacheText, '(?m)^VCPKG_INSTALLED_DIR:[^=]*=(.+)$')
$tripletMatch = [regex]::Match($cacheText, '(?m)^VCPKG_TARGET_TRIPLET:[^=]*=(.+)$')
if (-not $installedDirMatch.Success -or -not $tripletMatch.Success) {
  throw 'CMakeCache.txt does not identify the vcpkg installation and target triplet.'
}
$vcpkgInstalledDir = [IO.Path]::GetFullPath($installedDirMatch.Groups[1].Value.Trim())
$tripletRoot = Join-Path $vcpkgInstalledDir $tripletMatch.Groups[1].Value.Trim()
$tripletShare = Join-Path $tripletRoot 'share'
$vcpkgLicenseFiles = @(Get-ChildItem -LiteralPath $tripletShare -Directory | ForEach-Object {
  $licensePath = Join-Path $_.FullName 'copyright'
  if (Test-Path -LiteralPath $licensePath -PathType Leaf) { Get-Item -LiteralPath $licensePath }
})
$eigenInclude = Join-Path $tripletRoot 'include/eigen3'
if ($vcpkgLicenseFiles.Count -eq 0 -or -not (Test-Path -LiteralPath (Join-Path $eigenInclude 'Eigen') -PathType Container)) {
  throw 'The selected vcpkg triplet is missing license files or Eigen source headers.'
}
$cudaBinMatch = [regex]::Match($cacheText, '(?m)^CUDAToolkit_BIN_DIR:[^=]*=(.+)$')
if (-not $cudaBinMatch.Success) {
  $cudaCompilerMatch = [regex]::Match($cacheText, '(?m)^CMAKE_CUDA_COMPILER:[^=]*=(.+)$')
  if ($cudaCompilerMatch.Success) { $cudaBin = Split-Path -Parent $cudaCompilerMatch.Groups[1].Value.Trim() }
} else {
  $cudaBin = $cudaBinMatch.Groups[1].Value.Trim()
}
if ([string]::IsNullOrWhiteSpace($cudaBin)) { throw 'Could not locate the CUDA runtime DLL directory in CMakeCache.txt.' }

# Walk the PE import closure so only app-local dependencies are packaged.
$compilerMatch = [regex]::Match($cacheText, '(?m)^CMAKE_CXX_COMPILER:[^=]*=(.+)$')
$dumpbin = $null
if ($compilerMatch.Success) { $dumpbin = Join-Path (Split-Path -Parent $compilerMatch.Groups[1].Value.Trim()) 'dumpbin.exe' }
if ([string]::IsNullOrWhiteSpace($dumpbin) -or -not (Test-Path -LiteralPath $dumpbin -PathType Leaf)) {
  $dumpbinCommand = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
  if ($dumpbinCommand) { $dumpbin = $dumpbinCommand.Source }
}
if ([string]::IsNullOrWhiteSpace($dumpbin) -or -not (Test-Path -LiteralPath $dumpbin -PathType Leaf)) {
  throw 'Could not locate dumpbin.exe to audit the runtime DLL closure.'
}

$pending = [Collections.Generic.Queue[string]]::new()
$visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$runtimeDlls = [Collections.Generic.SortedDictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
$appLocalDllLicenseMap = @{
  'cudart64_12.dll' = 'NVIDIA CUDA Toolkit license, included in the runtime package.'
}
$systemDllLicenseMap = @{
  'bcrypt.dll' = 'Microsoft Windows component, supplied by Windows and not redistributed.'
  'dbghelp.dll' = 'Microsoft Windows component, supplied by Windows and not redistributed.'
  'kernel32.dll' = 'Microsoft Windows component, supplied by Windows and not redistributed.'
  'ole32.dll' = 'Microsoft Windows component, supplied by Windows and not redistributed.'
  'vcomp140.dll' = 'Microsoft Visual C++ 2015-2022 x64 Redistributable, external and not bundled.'
}
$cudart = Join-Path $cudaBin 'cudart64_12.dll'
$cudaLicense = Join-Path (Split-Path -Parent $cudaBin) 'LICENSE'
$pending.Enqueue($colmapExe)
while ($pending.Count -gt 0) {
  $modulePath = $pending.Dequeue()
  if (-not $visited.Add([IO.Path]::GetFullPath($modulePath))) { continue }
  $dependencies = & $dumpbin /dependents $modulePath 2>&1
  if ($LASTEXITCODE -ne 0) { throw "dumpbin failed while auditing $modulePath" }
  foreach ($line in $dependencies) {
    if ($line -notmatch '^\s+([A-Za-z0-9_.+-]+\.dll)\s*$') { continue }
    $dllName = $Matches[1]
    if ($dllName -match '^(?i:api-ms-win-|ext-ms-win-)') { continue }
    if ($dllName -match '^(?i:libgfortran|libquadmath|libgcc.*|libstdc\+\+.*|libgomp.*)\.dll$') {
      throw "Runtime dependency '$dllName' is GPL/LGPL-family; this build cannot be packaged. Use a COLMAP build whose BLAS/LAPACK dependency closure complies with the repository license policy."
    }

    $dependencyPath = Join-Path $exeDir $dllName
    if (-not (Test-Path -LiteralPath $dependencyPath -PathType Leaf)) { $dependencyPath = Join-Path $cudaBin $dllName }
    if (Test-Path -LiteralPath $dependencyPath -PathType Leaf) {
      $dependencyPath = [IO.Path]::GetFullPath($dependencyPath)
      if (-not $appLocalDllLicenseMap.ContainsKey($dllName)) {
        throw "Unclassified app-local DLL '$dllName' blocks packaging. Audit its license and redistribution terms before adding it to the explicit allowlist."
      }
      if ($dllName -ieq 'cudart64_12.dll' -and -not $dependencyPath.Equals([IO.Path]::GetFullPath($cudart), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'cudart64_12.dll must come from the CUDA Toolkit directory recorded by CMakeCache.txt.'
      }
      if (-not $runtimeDlls.ContainsKey($dllName)) { $runtimeDlls.Add($dllName, $dependencyPath) }
      $pending.Enqueue($dependencyPath)
      continue
    }

    $systemDll = Join-Path (Join-Path $env:SystemRoot 'System32') $dllName
    if (-not (Test-Path -LiteralPath $systemDll -PathType Leaf)) {
      throw "Unresolved non-system runtime dependency '$dllName' imported by $modulePath."
    }
    if (-not $systemDllLicenseMap.ContainsKey($dllName)) {
      throw "Unclassified System32 dependency '$dllName' blocks packaging. Audit its component and license before adding it to the explicit system dependency map."
    }
  }
}

if (-not (Test-Path -LiteralPath $cudart -PathType Leaf)) { throw "CUDA runtime DLL was not found: $cudart" }
if (-not (Test-Path -LiteralPath $cudaLicense -PathType Leaf)) { throw "CUDA license file was not found: $cudaLicense" }
foreach ($dll in $runtimeDlls.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $dll.Value -PathType Leaf)) { throw "Required runtime DLL was not found: $($dll.Key)" }
}

if (-not $runtimeDirectoryExists) { $null = New-Item -ItemType Directory -Path $runtimePath }
$binDir = Join-Path $runtimePath 'bin'
$scriptsDir = Join-Path $runtimePath 'scripts/run'
$licensesDir = Join-Path $runtimePath 'licenses'
$null = New-Item -ItemType Directory -Path $binDir
$null = New-Item -ItemType Directory -Path $scriptsDir -Force
$vcpkgLicensesDir = Join-Path $licensesDir 'vcpkg'
$null = New-Item -ItemType Directory -Path $vcpkgLicensesDir -Force
foreach ($licenseFile in $vcpkgLicenseFiles) {
  $licenseName = "$($licenseFile.Directory.Name).txt"
  Copy-Item -LiteralPath $licenseFile.FullName -Destination (Join-Path $vcpkgLicensesDir $licenseName)
}
$runtimeDllCount = $runtimeDlls.Count
$eigenSourceDir = Join-Path $licensesDir 'eigen3-source'
$null = New-Item -ItemType Directory -Path $eigenSourceDir -Force
Copy-Item -Path (Join-Path $eigenInclude '*') -Destination $eigenSourceDir -Recurse
Copy-Item -LiteralPath $colmapExe -Destination $binDir
foreach ($dll in $runtimeDlls.GetEnumerator()) { Copy-Item -LiteralPath $dll.Value -Destination $binDir }
if (-not $runtimeDlls.ContainsKey('cudart64_12.dll')) {
  Copy-Item -LiteralPath $cudart -Destination $binDir
  $runtimeDllCount++
}
Copy-Item -LiteralPath $runner -Destination $scriptsDir
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination $runtimePath
Copy-Item -LiteralPath (Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md') -Destination $runtimePath
Copy-Item -LiteralPath $cudaLicense -Destination (Join-Path $runtimePath 'NVIDIA_CUDA_LICENSE.txt')
Copy-Item -LiteralPath $readme -Destination (Join-Path $runtimePath 'README.md')

Write-Host "Packaged COLMAP runtime at $runtimePath"
Write-Host "Included $runtimeDllCount runtime DLLs, $($vcpkgLicenseFiles.Count) vcpkg license files, Eigen MPL source headers, project notices, NVIDIA CUDA license, and the pipeline script."

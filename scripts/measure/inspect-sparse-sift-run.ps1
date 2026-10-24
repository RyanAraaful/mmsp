[CmdletBinding()]
param(
  [string]$RunDir
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../env.ps1')

if ([string]::IsNullOrWhiteSpace($RunDir)) {
  $run = Get-ChildItem -LiteralPath $PrimaryRoot -Directory -Filter 'sparse-sift-117-*' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($null -eq $run) { throw 'No sparse SIFT experiment output was found.' }
  $RunDir = $run.FullName
}

$summaryPath = Join-Path $RunDir 'run-summary.json'
$databasePath = Join-Path $RunDir 'database.db'
$logPath = Join-Path $RunDir 'process-drone.log'
foreach ($path in @($summaryPath, $databasePath, $logPath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required experiment artifact is missing: $(Split-Path $path -Leaf)." }
}

$summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
Write-Host "STATUS=$($summary.status)"
Write-Host "PHOTOS=$($summary.inputPhotoCount)"
Write-Host "REGISTERED=$($summary.registeredPhotoCount)"
Write-Host "FUSED_POINTS=$($summary.fusedPointCount)"
Write-Host "DEPTH_MAPS=$($summary.depthMapCount)"
Write-Host "TOTAL_SECONDS=$($summary.totalSeconds)"
Write-Host "PEAK_VRAM_MB=$($summary.peakVramMb)"
Write-Host "VRAM_SAMPLES=$($summary.vramSampleCount)"
foreach ($stage in $summary.stageTimingsSeconds.PSObject.Properties) {
  Write-Host ("STAGE_{0}_SECONDS={1}" -f $stage.Name, $stage.Value)
}
$reprojection = Select-String -LiteralPath $logPath -Pattern 'Mean reprojection error:\s*([\d.]+)px' | Select-Object -Last 1
if ($reprojection -and $reprojection.Matches.Count -gt 0) {
  Write-Host "MEAN_REPROJECTION_ERROR_PX=$($reprojection.Matches[0].Groups[1].Value)"
}

$python = Get-Command python.exe -ErrorAction SilentlyContinue
$pythonLauncher = Get-Command py.exe -ErrorAction SilentlyContinue
$statsCode = 'import json,sqlite3,sys; c=sqlite3.connect(sys.argv[1]); p,n=c.execute("select count(*),coalesce(sum(rows),0) from two_view_geometries where config>1").fetchone(); m,k=c.execute("select count(*),coalesce(sum(rows),0) from matches").fetchone(); print(json.dumps({"verified_pairs":p,"inlier_matches":n,"matched_pairs":m,"raw_matches":k}))'
if ($python) {
  & $python.Source -c $statsCode $databasePath
  if ($LASTEXITCODE -ne 0) { throw 'Python could not read the experiment database.' }
} elseif ($pythonLauncher) {
  & $pythonLauncher.Source -3 -c $statsCode $databasePath
  if ($LASTEXITCODE -ne 0) { throw 'Python could not read the experiment database.' }
} else {
  if (-not ('MMSPSqlite' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MMSPSqlite {
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_open16", CharSet=CharSet.Unicode)] public static extern int Open(string filename, out IntPtr db);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_prepare_v2", CharSet=CharSet.Ansi)] public static extern int Prepare(IntPtr db, string sql, int bytes, out IntPtr stmt, IntPtr tail);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_step")] public static extern int Step(IntPtr stmt);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_column_int64")] public static extern long ColumnInt64(IntPtr stmt, int index);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_finalize")] public static extern int Finalize(IntPtr stmt);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_close")] public static extern int Close(IntPtr db);
}
'@
  }

  $db = [IntPtr]::Zero
  $stmt = [IntPtr]::Zero
  if ([MMSPSqlite]::Open($databasePath, [ref]$db) -ne 0) { throw 'Windows SQLite could not open the experiment database.' }
  try {
    $sql = 'SELECT COUNT(*), COALESCE(SUM(rows),0) FROM two_view_geometries WHERE config>1'
    if ([MMSPSqlite]::Prepare($db, $sql, -1, [ref]$stmt, [IntPtr]::Zero) -ne 0 -or [MMSPSqlite]::Step($stmt) -ne 100) {
      throw 'Windows SQLite could not read verified-pair statistics.'
    }
    $verifiedPairs = [MMSPSqlite]::ColumnInt64($stmt, 0)
    $inlierMatches = [MMSPSqlite]::ColumnInt64($stmt, 1)
    [void][MMSPSqlite]::Finalize($stmt)
    $stmt = [IntPtr]::Zero
    $sql = 'SELECT COUNT(*), COALESCE(SUM(rows),0) FROM matches'
    if ([MMSPSqlite]::Prepare($db, $sql, -1, [ref]$stmt, [IntPtr]::Zero) -ne 0 -or [MMSPSqlite]::Step($stmt) -ne 100) {
      throw 'Windows SQLite could not read raw-match statistics.'
    }
    $matchedPairs = [MMSPSqlite]::ColumnInt64($stmt, 0)
    $rawMatches = [MMSPSqlite]::ColumnInt64($stmt, 1)
    Write-Host "DATABASE_MATCH_STATS verified_pairs=$verifiedPairs inlier_matches=$inlierMatches matched_pairs=$matchedPairs raw_matches=$rawMatches"
  } finally {
    if ($stmt -ne [IntPtr]::Zero) { [void][MMSPSqlite]::Finalize($stmt) }
    [void][MMSPSqlite]::Close($db)
  }
}

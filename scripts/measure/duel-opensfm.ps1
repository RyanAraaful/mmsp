# OpenSfM duel vs hybrid SfM on Secondary 51 (plan Task 3). Smoke 3 photos
# first (reconstruction.json must validate) then the 51-photo duel + table.
# OpenSfM is an external benchmark process only; nothing of it enters the repo.
# No machine paths here; everything comes from env.local.ps1 via scripts/env.ps1.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
foreach ($v in @('PyEnv', 'MicromambaExe', 'OpenSfMRoot', 'SecondaryPhotos', 'SecondaryRoot')) {
  if ([string]::IsNullOrEmpty((Get-Variable $v -ValueOnly -ErrorAction SilentlyContinue))) {
    throw "$v is not set. See env.local.example.ps1."
  }
}
$osfm = Join-Path $OpenSfMRoot 'bin/opensfm_main.py'
if (-not (Test-Path $osfm)) { throw "opensfm_main.py not found: $osfm" }

function Invoke-Stage($cmd, $ds, $log) {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $MicromambaExe run -p $PyEnv python $osfm $cmd $ds 2>&1 | Tee-Object $log
  $code = $LASTEXITCODE
  $sw.Stop()
  return @{ Code = $code; WallS = $sw.Elapsed.TotalSeconds }
}

function Test-Reconstruction($ds) {
  $rec = Join-Path $ds 'reconstruction.json'
  if (-not (Test-Path $rec)) { return @{ Valid = $false } }
  $info = & $MicromambaExe run -p $PyEnv python -c @'
import json, sys
rec = json.load(open(sys.argv[1]))
r0 = rec[0]
shots = r0.get("shots", {})
pts = r0.get("points", {})
print("shots=%d points=%d" % (len(shots), len(pts)))
'@ $rec 2>&1
  return @{ Valid = ($LASTEXITCODE -eq 0); Info = ($info | Out-String).Trim() }
}

function Invoke-DuelSet($name, $srcImages, $proj) {
  New-Item -ItemType Directory -Force (Join-Path $proj 'images') | Out-Null
  Copy-Item (Join-Path $srcImages '*.jpg') (Join-Path $proj 'images/') -Force
  $walls = @{}
  foreach ($stage in @('extract_metadata', 'detect_features', 'match_features', 'create_tracks', 'reconstruct', 'compute_statistics')) {
    $r = Invoke-Stage $stage $proj (Join-Path $proj "log_$stage.txt")
    $walls[$stage] = $r.WallS
    '{0} {1}: exit={2} wall_s={3:N0}' -f $name, $stage, $r.Code, $r.WallS
    if ($r.Code -ne 0) { throw "$name stage $stage failed with exit $($r.Code)" }
  }
  $t = Test-Reconstruction $proj
  '{0} reconstruction: valid={1} {2}' -f $name, $t.Valid, $t.Info
  if (-not $t.Valid) { throw "$name reconstruction.json invalid" }
  return $walls
}

$smoke = Join-Path $SecondaryRoot 'opensfm-smoke'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
New-Item -ItemType Directory -Force (Join-Path $smoke 'images') | Out-Null
Copy-Item "$SecondaryPhotos/dji_fly_20250814_073022_877_1755132223527_photo.jpg" (Join-Path $smoke 'images/') -Force
Copy-Item "$SecondaryPhotos/dji_fly_20250814_073026_878_1755132222165_photo.jpg" (Join-Path $smoke 'images/') -Force
Copy-Item "$SecondaryPhotos/dji_fly_20250814_073028_879_1755132220831_photo.jpg" (Join-Path $smoke 'images/') -Force
$wsmoke = Invoke-DuelSet 'SMOKE' (Join-Path $smoke 'images') $smoke
$sw.Stop()
'SMOKE total wall_s={0:N0}' -f $sw.Elapsed.TotalSeconds

$duel = Join-Path $SecondaryRoot 'opensfm-duel'
$wduel = Invoke-DuelSet 'DUEL' $SecondaryPhotos $duel
'DUEL walls (s): ' + (($wduel.Keys | Sort-Object | ForEach-Object { "$_=$([int]$wduel[$_])" }) -join ' ')
exit 0

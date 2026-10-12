$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$dir = "$CloudCompareDir"
foreach ($dll in @('CCAppCommon.dll', 'QCC_DB_LIB.dll')) {
  $bytes = [System.IO.File]::ReadAllBytes("$dir\$dll")
  $uni = [System.Text.Encoding]::Unicode.GetString($bytes)
  $asc = [System.Text.Encoding]::ASCII.GetString($bytes)
  foreach ($pat in @('-SILENT', '-SAVE_CLOUDS', '-VIEW', 'RENDER_TO_FILE', 'SAVE_IMAGE')) {
    Write-Host ("$dll :: $pat uni=" + ($uni.IndexOf($pat) -ge 0) + " asc=" + ($asc.IndexOf($pat) -ge 0))
  }
}

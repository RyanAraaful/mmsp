$ErrorActionPreference = 'Continue'
$log = 'E:/dev/Lewoleba-15agustus/log_patch_pyramid1.txt'
Write-Host ("geometric_writes=" + @(Select-String 'Writing geometric output' $log).Count)
Write-Host ("photometric_writes=" + @(Select-String 'Writing photometric output' $log).Count)
Write-Host ("ignoring=" + @(Select-String 'Ignoring reference image' $log).Count)
Select-String 'Elapsed time' $log | Select-Object -First 1 -Last 1

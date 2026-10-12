$ErrorActionPreference = 'Continue'
$exe = 'E:\CloudCompare_v2.13.2_bin_x64\CloudCompare_v2.13.2.preview_bin_x64\CloudCompare.exe'
& $exe -HELP > 'E:\dev\Colmap-Kernel\scripts\setup\cchelp.txt' 2>&1
Write-Host ("exit=" + $LASTEXITCODE)
Get-Content 'E:\dev\Colmap-Kernel\scripts\setup\cchelp.txt' -TotalCount 60

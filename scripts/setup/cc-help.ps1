$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$exe = "$CloudCompareDir\CloudCompare.exe"
& $exe -HELP > "$RepoRoot\scripts\setup\cchelp.txt" 2>&1
Write-Host ("exit=" + $LASTEXITCODE)
Get-Content "$RepoRoot\scripts\setup\cchelp.txt" -TotalCount 60

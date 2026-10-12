$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$exe = "$CloudCompareDir\CloudCompare.exe"
Remove-Item "$PrimaryRoot/cc_raster_test*" -Force -ErrorAction SilentlyContinue
& $exe -SILENT -O "$PrimaryRoot/dense700/fused_base.ply" -RASTERIZE -GRID_STEP 0.5 -OUTPUT_RASTER 2>&1 | Select-Object -Last 15
Write-Host ("exit=" + $LASTEXITCODE)
Get-ChildItem "$PrimaryRoot/dense700/" -Filter '*raster*' -ErrorAction SilentlyContinue | Select-Object Name, Length
Get-ChildItem "$PrimaryRoot/" -Filter '*raster*' -ErrorAction SilentlyContinue | Select-Object Name, Length
Stop-Process -Name CloudCompare -Force -ErrorAction SilentlyContinue

$ErrorActionPreference = 'Continue'
$exe = 'E:\CloudCompare_v2.13.2_bin_x64\CloudCompare_v2.13.2.preview_bin_x64\CloudCompare.exe'
Remove-Item 'E:/dev/Lewoleba-15agustus/cc_raster_test*' -Force -ErrorAction SilentlyContinue
& $exe -SILENT -O 'E:/dev/Lewoleba-15agustus/dense700/fused_base.ply' -RASTERIZE -GRID_STEP 0.5 -OUTPUT_RASTER 2>&1 | Select-Object -Last 15
Write-Host ("exit=" + $LASTEXITCODE)
Get-ChildItem 'E:/dev/Lewoleba-15agustus/dense700/' -Filter '*raster*' -ErrorAction SilentlyContinue | Select-Object Name, Length
Get-ChildItem 'E:/dev/Lewoleba-15agustus/' -Filter '*raster*' -ErrorAction SilentlyContinue | Select-Object Name, Length
Stop-Process -Name CloudCompare -Force -ErrorAction SilentlyContinue

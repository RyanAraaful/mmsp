$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$omvsBin = "$OpenMVSRoot/build-mx150/bin/vc17/x64"
$proj = "$SecondaryRoot"
$work = "$proj/openmvs"
mkdir $work -Force | Out-Null
Copy-Item "$CudaEnv/bin/cudart64_12.dll", "$CudaEnv/bin/curand64_10.dll" "$omvsBin/" -Force
Set-Location $omvsBin
& './InterfaceCOLMAP.exe' -i "$proj/dense" -o "$work/scene.mvs" 2>&1 | Select-Object -Last 4
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$sc = Get-Item "$work/scene.mvs"
Write-Output ("scene.mvs MB=" + [math]::Round($sc.Length / 1MB, 2))
$sampler = Start-Process powershell -ArgumentList '-NoProfile', '-Command', "while (Get-Process DensifyPointCloud -ErrorAction SilentlyContinue) { ((nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits) + ',' + (Get-Date -Format 'HH:mm:ss')) | Out-File '$work/vram_openmvs.csv' -Append; Start-Sleep 5 }" -PassThru
Set-Location $work
$start = Get-Date
& "$omvsBin/DensifyPointCloud.exe" -i 'scene.mvs' -o 'scene_dense.mvs' --resolution-level 1 --max-resolution 2560 --min-resolution 640 --number-views 8 --number-views-fuse 2 --iters 4 --geometric-iters 2 --fusion-filter 2 2>&1 | Tee-Object "$work/log_densify.txt"
$mins = ((Get-Date) - $start).TotalMinutes
Write-Output ("DENSIFY_MINUTES=" + [math]::Round($mins, 2))
Stop-Process -Id $sampler.Id -Force -ErrorAction SilentlyContinue
exit 0

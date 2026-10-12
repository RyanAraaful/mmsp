$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
Copy-Item "$CudaEnv/bin/cudart64_12.dll", "$CudaEnv/bin/curand64_10.dll" "$OpenMVSRoot/build-mx150/bin/vc17/x64/" -Force
Set-Location "$OpenMVSRoot/build-mx150/bin/vc17/x64"
& './InterfaceCOLMAP.exe' -i "$PrimaryRoot/dense" -o "$PrimaryRoot/openmvs/scene.mvs" 2>&1 | Select-Object -Last 4
$sc = Get-Item "$PrimaryRoot/openmvs/scene.mvs"
Write-Output ("scene.mvs MB=" + [math]::Round($sc.Length / 1MB, 2))

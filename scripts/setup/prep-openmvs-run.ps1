$ErrorActionPreference = 'Continue'
Copy-Item 'E:/dev/tools/cuda-env/bin/cudart64_12.dll', 'E:/dev/tools/cuda-env/bin/curand64_10.dll' 'E:/dev/openMVS/build-mx150/bin/vc17/x64/' -Force
Set-Location 'E:/dev/openMVS/build-mx150/bin/vc17/x64'
& './InterfaceCOLMAP.exe' -i 'E:/dev/Lewoleba-15agustus/dense' -o 'E:/dev/Lewoleba-15agustus/openmvs/scene.mvs' 2>&1 | Select-Object -Last 4
$sc = Get-Item 'E:/dev/Lewoleba-15agustus/openmvs/scene.mvs'
Write-Output ("scene.mvs MB=" + [math]::Round($sc.Length / 1MB, 2))

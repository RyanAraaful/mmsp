# run-ablate.ps1 — frozen ablation harness for MVS speed+density plan (Task 0).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File run-ablate.ps1 -Label <nama> [-ExtraArgs '<flags tambahan>']
# Produces (in E:\dev\Lewoleba-15agustus\): log_patch_<label>.txt, log_fusion_<label>.txt,
# vram_<label>.csv, fused_<label>.ply (+ fused.ply baseline-compatible); prints points/time/hash.
# Mirrors g3-patch700.ps1 baseline flags @700px; undistort is NOT rerun (dense700/ reused).
param(
  [Parameter(Mandatory = $true)][string]$Label,
  [string]$ExtraArgs = '',
  [string]$FusionInputType = 'geometric',
  [string]$FusionExtraArgs = '',
  [string]$Workspace = 'E:\dev\Lewoleba-15agustus\dense700'
)
$ErrorActionPreference = 'Continue'
$env:CUDA_PATH = 'E:\dev\tools\cuda-env'
$env:CUDA_HOME = 'E:\dev\tools\cuda-env'
$env:CUDAToolkit_ROOT = 'E:\dev\tools\cuda-env'
$env:PATH = 'E:\dev\tools\cuda-env\bin;' + $env:PATH
$colmap = 'E:\dev\Colmap-Kernel\colmap\build-mx150\src\colmap\exe\colmap.exe'
$dense = $Workspace
$outdir = Split-Path $dense -Parent
if (!(Test-Path "$dense\stereo\patch-match.cfg.full")) { Copy-Item "$dense\stereo\patch-match.cfg" "$dense\stereo\patch-match.cfg.full" -Force } # guard: keep first backup, g3 overwrote it each run
(Get-Content "$dense\stereo\patch-match.cfg.full") -replace '__auto__, \d+', '__auto__, 8' | Out-File -Encoding ascii "$dense\stereo\patch-match.cfg"
$vramCsv = "$outdir\vram_$Label.csv"
if (Test-Path $vramCsv) { Remove-Item $vramCsv -Force }
$t0 = Get-Date
$sampler = Start-Process powershell -ArgumentList '-NoProfile', '-Command', "while (Get-Process colmap -ErrorAction SilentlyContinue) { ((nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits) + ',' + (Get-Date -Format 'HH:mm:ss')) | Out-File '$vramCsv' -Append; Start-Sleep 5 }" -PassThru
try {
  $patchArgs = @('patch_match_stereo', '--workspace_path', $dense, '--workspace_format', 'COLMAP',
    '--PatchMatchStereo.max_image_size', '700', '--PatchMatchStereo.gpu_index', '0',
    '--PatchMatchStereo.window_radius', '5', '--PatchMatchStereo.window_step', '1',
    '--PatchMatchStereo.num_samples', '10', '--PatchMatchStereo.num_iterations', '4',
    '--PatchMatchStereo.min_triangulation_angle', '1.0', '--PatchMatchStereo.max_triangulation_angle', '65.0',
    '--PatchMatchStereo.geom_consistency', '1', '--PatchMatchStereo.geom_consistency_regularizer', '0.3',
    '--PatchMatchStereo.geom_consistency_max_cost', '3.0', '--PatchMatchStereo.filter', '1',
    '--PatchMatchStereo.filter_min_ncc', '0.15', '--PatchMatchStereo.filter_min_triangulation_angle', '3.0',
    '--PatchMatchStereo.filter_min_num_consistent', '2', '--PatchMatchStereo.filter_geom_consistency_max_cost', '1.0',
    '--PatchMatchStereo.cache_size', '4')
  if ($ExtraArgs -ne '') {
    # ExtraArgs OVERRIDES baseline flags (gflags fatal bila flag ganda).
    $extraTokens = @($ExtraArgs -split '\s+' | Where-Object { $_ -ne '' })
    $overrideFlags = @($extraTokens | Where-Object { $_ -like '--*' })
    $filtered = @($patchArgs[0])
    $i = 1
    while ($i -lt $patchArgs.Count) {
      $flag = $patchArgs[$i]
      if (($flag -like '--*') -and ($overrideFlags -contains $flag)) { $i += 2; continue }
      $filtered += $flag
      if ($i + 1 -lt $patchArgs.Count) { $filtered += $patchArgs[$i + 1] }
      $i += 2
    }
    $patchArgs = $filtered + $extraTokens
  }
  & $colmap @patchArgs 2>&1 | Tee-Object "$outdir\log_patch_$Label.txt"
  if ($LASTEXITCODE -ne 0) { throw "patch_match_stereo exit $LASTEXITCODE - aborting before fusion" }
  $mapsWritten = @(Get-ChildItem "$dense/stereo/depth_maps/*.bin" -ErrorAction SilentlyContinue).Count
  if ($mapsWritten -eq 0) { throw 'no depth maps written - aborting before fusion' }
  $fusionArgs = @('stereo_fusion', '--workspace_path', $dense, '--workspace_format', 'COLMAP', '--input_type', $FusionInputType, '--output_path', "$dense\fused_$Label.ply", '--StereoFusion.max_image_size', '700', '--StereoFusion.min_num_pixels', '3', '--StereoFusion.max_reproj_error', '4.0', '--StereoFusion.max_depth_error', '0.05', '--StereoFusion.max_normal_error', '20.0', '--StereoFusion.check_num_images', '30', '--StereoFusion.cache_size', '4')
  if ($FusionExtraArgs -ne '') { $fusionArgs += @($FusionExtraArgs -split '\s+' | Where-Object { $_ -ne '' }) } # hanya flag BARU (tanpa dedupe ala patch)
  & $colmap @fusionArgs 2>&1 | Tee-Object "$outdir\log_fusion_$Label.txt"
} finally {
  Stop-Process -Id $sampler.Id -Force -ErrorAction SilentlyContinue
}
$match = Select-String 'Number of fused points: (\d+)' "$outdir\log_fusion_$Label.txt" | Select-Object -Last 1
$points = if ($match) { [int]$match.Matches[0].Groups[1].Value } else { -1 }
if ($points -le 0) { throw "fusion produced $points points - fused.ply left untouched" }
Copy-Item "$dense\fused_$Label.ply" "$dense\fused.ply" -Force # baseline-compatible only on success
Select-String 'Number of fused points|Elapsed time' "$outdir\log_patch_$Label.txt", "$outdir\log_fusion_$Label.txt"
'WALL TOTAL: {0}' -f ((Get-Date) - $t0)
Get-FileHash "$dense\fused_$Label.ply"
# VIEWPOINT PIN (Task 0): render dense700/fused.ply vs openmvs/scene_dense.ply from same
# cameras -> view-nadir-base.png / view-oblik-base.png. No headless renderer on this box
# (no model_viewer GUI build, no CloudCompare/Meshlab CLI found), so the exact render is
# deferred to the dry-run step on a machine with a viewer; candidate commands:
#   CloudCompare -SILENT -O E:/dev/Lewoleba-15agustus/dense700/fused.ply -O E:/dev/Lewoleba-15agustus/openmvs/scene_dense.ply -VIEW TOP -SAVE_IMAGE view-nadir-base.png
#   (then -VIEW ISO / custom azimuth for oblik -> view-oblik-base.png)
exit 0

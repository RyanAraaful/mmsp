$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$ncu = "$NcuExe"
$colmap = "$ColmapExe"
$dense = "$PrimaryRoot\dense700"
$outdir = "$PrimaryRoot"
$stereo = "$dense\stereo"
$backup = "$stereo\backup_pre_ncu"
New-Item -ItemType Directory -Force "$backup\depth_maps" | Out-Null
New-Item -ItemType Directory -Force "$backup\normal_maps" | Out-Null
foreach ($f in @(Get-ChildItem "$stereo\depth_maps\*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$backup\depth_maps\" -Force }
foreach ($f in @(Get-ChildItem "$stereo\normal_maps\*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$backup\normal_maps\" -Force }
& $ncu -o "$outdir\ncu_sweep_r3" --target-processes all -k regex:SweepFromTopToBottom --launch-skip 5 --launch-count 1 --section SpeedOfLight --section Occupancy --section MemoryWorkloadAnalysis $colmap patch_match_stereo --workspace_path $dense --workspace_format COLMAP --PatchMatchStereo.max_image_size 700 --PatchMatchStereo.gpu_index 0 --PatchMatchStereo.window_radius 3 --PatchMatchStereo.window_step 2 --PatchMatchStereo.num_samples 10 --PatchMatchStereo.num_iterations 1 --PatchMatchStereo.min_triangulation_angle 1.0 --PatchMatchStereo.max_triangulation_angle 65.0 --PatchMatchStereo.geom_consistency 1 --PatchMatchStereo.geom_consistency_regularizer 0.3 --PatchMatchStereo.geom_consistency_max_cost 3.0 --PatchMatchStereo.filter 1 --PatchMatchStereo.filter_min_ncc 0.15 --PatchMatchStereo.filter_min_triangulation_angle 3.0 --PatchMatchStereo.filter_min_num_consistent 2 --PatchMatchStereo.filter_geom_consistency_max_cost 1.0 --PatchMatchStereo.pyramid_levels 1 --PatchMatchStereo.filter_min_confidence 0.2 --PatchMatchStereo.cache_size 4
$mapsWritten = @(Get-ChildItem "$stereo/depth_maps/*.bin" -ErrorAction SilentlyContinue).Count
"DEPTH_MAPS_WRITTEN: $mapsWritten"
"NCU_REPORT: $outdir\ncu_sweep_r3.ncu-rep"
exit 0

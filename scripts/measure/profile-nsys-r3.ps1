$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '../env.ps1')
$nsys = "$NsysExe"
$colmap = "$ColmapExe"
$dense = "$LewolebaRoot\dense700"
$outdir = "$LewolebaRoot"
$stereo = "$dense\stereo"
$backup = "$stereo\backup_pre_nsys"
New-Item -ItemType Directory -Force "$backup\depth_maps" | Out-Null
New-Item -ItemType Directory -Force "$backup\normal_maps" | Out-Null
foreach ($f in @(Get-ChildItem "$stereo\depth_maps\*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$backup\depth_maps\" -Force }
foreach ($f in @(Get-ChildItem "$stereo\normal_maps\*.bin" -ErrorAction SilentlyContinue)) { Move-Item $f.FullName "$backup\normal_maps\" -Force }
if (!(Test-Path "$stereo\patch-match.cfg.full")) { Copy-Item "$stereo\patch-match.cfg" "$stereo\patch-match.cfg.full" -Force }
(Get-Content "$stereo\patch-match.cfg.full") -replace '__auto__, \d+', '__auto__, 8' | Out-File -Encoding ascii "$stereo\patch-match.cfg"
& $nsys profile --trace=cuda,nvtx --force-overwrite=true -o "$outdir\nsys_r3_patch" $colmap patch_match_stereo --workspace_path $dense --workspace_format COLMAP --PatchMatchStereo.max_image_size 700 --PatchMatchStereo.gpu_index 0 --PatchMatchStereo.window_radius 3 --PatchMatchStereo.window_step 2 --PatchMatchStereo.num_samples 10 --PatchMatchStereo.num_iterations 1 --PatchMatchStereo.min_triangulation_angle 1.0 --PatchMatchStereo.max_triangulation_angle 65.0 --PatchMatchStereo.geom_consistency 1 --PatchMatchStereo.geom_consistency_regularizer 0.3 --PatchMatchStereo.geom_consistency_max_cost 3.0 --PatchMatchStereo.filter 1 --PatchMatchStereo.filter_min_ncc 0.15 --PatchMatchStereo.filter_min_triangulation_angle 3.0 --PatchMatchStereo.filter_min_num_consistent 2 --PatchMatchStereo.filter_geom_consistency_max_cost 1.0 --PatchMatchStereo.pyramid_levels 1 --PatchMatchStereo.filter_min_confidence 0.2 --PatchMatchStereo.cache_size 4
$mapsWritten = @(Get-ChildItem "$stereo/depth_maps/*.bin" -ErrorAction SilentlyContinue).Count
"DEPTH_MAPS_WRITTEN: $mapsWritten"
"NSYS_REPORT: $outdir\nsys_r3_patch.nsys-rep"
exit 0

# MMSP — Multi-view Mapping & Stereo Processing

MMSP is a drone-oriented photogrammetry engine covering the full
pipeline from photos to **dense point cloud**: feature extraction and
matching → Structure-from-Motion → undistortion → PatchMatch stereo →
fusion. It is based on COLMAP, customized for nadir DJI drone imagery
on low-VRAM GPUs (developed and benchmarked on a 2 GB MX150, sm_61),
and positioned as an alternative to OpenSfM and OpenMVS for the
photos-to-dense-cloud stages.

V1 scope ends at the fused dense point cloud. Meshing, texturing and
orthomosaics are explicitly non-goals for V1.

Upstream base: COLMAP at `bd1fcf6` (the pristine snapshot is the first
commit in this repo's history; engine work sits on top in isolated
commits).

## Results (700 px working resolution)

| Dataset | Points | Depth + fusion | Throughput vs OpenMVS DensifyPointCloud | Holes | C2C median | Outlier |
|---|---|---|---|---|---|---|
| Lewoleba (117 photos) | 3,563,973 | 1.90 + 0.51 min | 1.48M vs 1.55M pts/min (**0.95x**) | 0 cells | 4.3 cm | 9.0% vs 3.4% |
| Midai (51 photos) | 1,721,491 | 0.81 + 0.20 min | 1.71M vs 2.52M pts/min (**0.68x**) | 1 cell | 4.3 cm | 7.2% vs 4.7% |

Quality oracle is fully numeric (`tools/metrics.cpp`): 0.5 m occupancy
coverage both ways, bidirectional cloud-to-cloud on 50k samples,
median+3MAD outlier ratio. OpenMVS is used only as an external,
separately-run benchmark — no OpenMVS code is in this tree.

## Engine changes (`colmap/src/colmap/mvs/`)

- **Sweep block 64** (`SWEEP_THREADS_PER_BLOCK` in `patch_match_cuda.cu`):
  the 1D per-column sweep kernels ran at ~11% occupancy ceiling with 32
  threads/block on a 3-SM GPU. Element-wise kernels stay at 32
  (32×32 = 1024 = architectural max). Measured −3% depth time on both
  datasets with no point loss.
- **Rotate ping-pong buffers** (`PatchMatchCuda::Rotate`): per-sweep
  `cudaMalloc`/`cudaFree` churn for the 7 rotated maps replaced with
  once-per-view spare buffers (less VRAM churn/fragmentation).
- **DENSE_SCHUR policy** for small drone projects (the upstream
  `SPARSE_SCHUR+EIGEN_SPARSE` path fails deterministically without
  SuiteSparse; see MODS.md).
- New (default-off, upstream behavior intact) options: `single_pass`,
  `pyramid_levels`, `filter_min_confidence`, `fuse_prior_weight`,
  plus relaxed fusion gates that won on benchmarks.

Full ablation history with rejected alternatives is in MODS.md.

## Winning configurations

Lewoleba: `pyramid_levels 1`, `filter_min_confidence 0.2`,
`window_step 2`, `num_iterations 1`, `window_radius 3`,
`StereoFusion.fuse_prior_weight 1.0`, `StereoFusion.max_depth_error 0.1`,
`max_triangulation_angle 65`.

Midai: same, except `window_radius 5`.

## Layout

- `colmap/` — engine source (upstream base plus the changes above)
- `scripts/run/` — dense ablation harness + per-experiment launchers
- `scripts/measure/` — profiler wrappers, check scripts, `metrics-*.ps1`
- `scripts/setup/` — build/configure, SfM, undistort, compare helpers
- `tools/` — `metrics.cpp` (dependency-free C++17 numeric metrics)
- `docs/` — design doc, per-task briefs/reports, progress ledger
- `MODS.md` — source of truth: plan, decisions, full benchmark tables

## Build (example: Windows + MSVC + CUDA)

Requires: Visual Studio 2022 (MSVC 19.34+), CUDA toolkit 12.x with an
`sm_61`-capable driver, vcpkg. Point `CUDA_PATH`/`CUDA_HOME`/
`CUDAToolkit_ROOT` at your toolkit and put its `bin/` on `PATH`
(`scripts/setup/configure-mx150.ps1` is an example), then the equivalent
of `scripts/setup/build-mx150.ps1`
(`cmake --build <build-dir> --config Release`).

Do not rebuild while a run is in progress (Windows file lock). Each
ablation moves `depth_maps/*.bin` + `normal_maps/*.bin` into a
`backup_pre_<label>/` subdirectory first — depth/normal maps share file
names, so separate subdirectories are mandatory.

## Run (photos → dense cloud)

```powershell
# 1. extract + match + map (CPU SIFT), then undistort (see scripts/setup/)
# 2. dense patch-match + fusion at 700 px (Lewoleba winner shown)
colmap patch_match_stereo --workspace_path <dense-workspace> \
  --workspace_format COLMAP --PatchMatchStereo.max_image_size 700 \
  --PatchMatchStereo.gpu_index 0 --PatchMatchStereo.window_radius 3 \
  --PatchMatchStereo.window_step 2 --PatchMatchStereo.num_iterations 1 \
  --PatchMatchStereo.min_triangulation_angle 1.0 \
  --PatchMatchStereo.max_triangulation_angle 65.0 \
  --PatchMatchStereo.pyramid_levels 1 \
  --PatchMatchStereo.filter_min_confidence 0.2
colmap stereo_fusion --workspace_path <dense-workspace> \
  --workspace_format COLMAP --input_type geometric \
  --output_path <fused.ply> --StereoFusion.max_depth_error 0.1 \
  --StereoFusion.fuse_prior_weight 1.0
```

```powershell
# numeric quality report vs a reference cloud
cl /O2 /std:c++17 tools\metrics.cpp   # -> metrics.exe
metrics.exe <ours.ply> <reference.ply> --pgm <holemap-prefix>
```

## License

- `colmap/` is upstream COLMAP (BSD-style, see its headers) plus the
  engine modifications listed above.
- `scripts/`, `tools/metrics.cpp`, `docs/`, `MODS.md` in this repo are
  original work for this project.
- License intent is permissive (anyone may use); final license text is
  pending audit. No GPL/AGPL code is built or executed here. SiftGPU is
  never executed; the pipeline runs CPU SIFT.

# MMSP — Multi-view Mapping & Stereo Processing

MMSP is a drone-oriented photogrammetry engine covering the pipeline
from photos to **dense point cloud**: feature extraction and matching →
Structure-from-Motion → undistortion → PatchMatch stereo → fusion. It is
based on COLMAP, customized for nadir drone imagery on low-VRAM GPUs,
and positioned as an alternative to OpenSfM and OpenMVS for the
photos-to-dense-cloud stages.

V1 scope ends at the fused dense point cloud. Meshing, texturing and
orthomosaics are explicitly non-goals for V1.

- Current state: dense stage beats the stock baseline ~23x in
  points/minute on the primary dataset at near-parity throughput with
  OpenMVS DensifyPointCloud (0.95x) with zero-hole coverage on both
  benchmark sites. Full benchmark tables live in `MODS.md`.
- Upstream base: COLMAP at `bd1fcf6` (pristine snapshot = first commit;
  engine work sits on top in isolated commits).

## Requirements

- Windows + Visual Studio 2022 (MSVC 19.34+), CUDA toolkit 12.x,
  `sm_61`-capable NVIDIA driver, vcpkg
- Point `CUDA_PATH` / `CUDA_HOME` / `CUDAToolkit_ROOT` at your toolkit
  and put its `bin/` on `PATH` (`scripts/setup/configure-mx150.ps1`
  is an example)

## Quickstart

```powershell
# 1. build (never rebuild while a run is in progress: Windows file lock)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup/build-mx150.ps1

# 2. dense patch-match + fusion at 700 px (Lewoleba winning flags shown)
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

# 3. numeric quality report vs a reference cloud (dependency-free C++17)
cl /O2 /std:c++17 tools\metrics.cpp   # -> metrics.exe
metrics.exe <ours.ply> <reference.ply> --pgm <holemap-prefix>
```

SfM + undistort + OpenMVS-compare helpers live in `scripts/setup/`;
the frozen dense harness is `scripts/run/run-ablate.ps1`.

## Layout

- `colmap/` — engine source (upstream base plus `mvs/` modifications)
- `scripts/run/` — ablation harness + per-experiment launchers
- `scripts/measure/` — profiler wrappers, check scripts, `metrics-*.ps1`
- `scripts/setup/` — build/configure, SfM, undistort, compare helpers
- `tools/` — `metrics.cpp`, `parsecheck.ps1`
- `docs/` — design doc, per-task briefs/reports, progress ledger
- `MODS.md` — source of truth: plan, decisions, full benchmark tables

## Contributing

Workflow (enforced on every change):

1. **Scope first** — engine scope is `mvs/` plus its option plumbing;
   touch a shared function only after grepping all callers, and fix root
   causes once in shared code.
2. **Evidence before claims** — new logic needs a measured check first
   (benchmark numbers, not guesses); one load-bearing issue found means
   saying so clearly. Ablations go through `scripts/run/run-ablate.ps1`
   with a label, and every run moves `depth_maps/*.bin` +
   `normal_maps/*.bin` into a `backup_pre_<label>/` subdirectory first
   (both map types share file names — separate subdirectories are
   mandatory). Verdicts (keep/reject) are recorded in `MODS.md` with
   numbers before any follow-up.
3. **Smallest complete diff** — no new dependency, abstraction, option or
   config nobody asked for; mark known limits as
   `shortcut: <limit>, <when to upgrade>`.
4. **Portability & hygiene** — PowerShell goes in `.ps1` files (never
   inline `$`); validate every script with `tools/parsecheck.ps1`;
   never commit build outputs, binaries, run logs, or credentials
   (see `.gitignore`); keep the tree GPL/AGPL-free.
5. **Atomic commits** — upstream baseline, kernel work, scripts, and
   docs go in separate commits; push only rebased, reviewable history.

## License

- `colmap/` is upstream COLMAP (BSD-style, see its headers) plus the
  engine modifications in the `kernel ...` commit(s).
- `scripts/`, `tools/metrics.cpp`, `docs/`, `MODS.md` in this repo are
  original work for this project.
- License intent is permissive (anyone may use); final license text is
  pending audit. No GPL/AGPL code is built or executed here. SiftGPU is
  never executed; the pipeline runs CPU SIFT.

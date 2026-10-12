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

## First-time setup (contributors)

Scripts never hardcode machine paths. Everything machine-specific lives
in one gitignored file:

```powershell
Copy-Item env.local.example.ps1 env.local.ps1
# then fill in your CUDA toolkit, dataset, vcpkg and tool paths
```

`scripts/env.ps1` (auto-sourced by every script) resolves the repo root
from its own location and reads your values. Alternatively set
`MMSP_CUDA_HOME` / `MMSP_LEWOLEBA_ROOT` / `MMSP_MIDAI_ROOT` environment
variables. Without them, scripts fail fast with a pointer to the template
instead of cryptic errors.

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

Workflow (scope first, evidence before claims, smallest complete diff,
atomic commits) — full contract in [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

- Original MMSP work is under the Apache License 2.0 — see `LICENSE`.
  Third-party attributions live in `THIRD_PARTY_NOTICES.md` (ship both
  files with any distribution).
- `colmap/` is upstream COLMAP (BSD-3-Clause) plus the engine
  modifications in the `kernel ...` commit(s).
- No GPL/AGPL code is built or executed here. SiftGPU is removed from
  the tree (never present in binaries); the pipeline runs CPU SIFT.

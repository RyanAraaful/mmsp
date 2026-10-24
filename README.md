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
`MMSP_CUDA_HOME` / `MMSP_PRIMARY_ROOT` / `MMSP_SECONDARY_ROOT` environment
variables. Without them, scripts fail fast with a pointer to the template
instead of cryptic errors.

## Quickstart

With the local COLMAP build and `env.local.ps1` configured, process a
folder of drone JPGs with one command. Choose a new or empty output folder
outside the repository:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run/process-drone.ps1 `
  -ImagesPath <drone-photo-folder> `
  -OutputDir <new-output-folder>
```

The output folder contains `dense/fused.ply`, `run-summary.json`,
`process-drone.log`, the SfM database and sparse model, and the dense
workspace. A failed stage returns a nonzero exit code and a failed summary.
The runner uses CPU SIFT and the benchmarked 700 px dense configuration.
It does not modify the source photos.

## External process contract

The runner can be called as a child process. Pass `-ColmapExe` to select a
standalone or non-default executable; `-GpuIndex` selects the PatchMatch GPU
and VRAM sampler (default `0`). The development default remains the executable
resolved by `scripts/env.ps1`.

Each stage writes a line beginning `MMSP_STAGE_EVENT ` followed by compact
JSON with `schemaVersion`, `stage`, `status`, and `timestampUtc`; status is
`started`, `completed`, or `failed`. The caller can ignore the COLMAP log
lines and parse these events directly. A stage reports `completed` only after
its expected output passes validation. `run-summary.json` keeps its existing
fields and adds `schemaVersion: 1` and `fusedCloudPath: "dense/fused.ply"`,
relative to `OutputDir`. A successful run exits `0`; a failed run exits
nonzero and records `status: "failed"`.

For point-cloud metrics against a reference cloud, build the existing
dependency-free C++17 tool with `cl /O2 /std:c++17 tools\metrics.cpp`, then
run `metrics.exe <ours.ply> <reference.ply> --pgm <holemap-prefix>`.

The frozen dense ablation harness remains in `scripts/run/run-ablate.ps1`.

## Layout

- `colmap/` — engine source (upstream base plus `mvs/` modifications)
- `scripts/run/` — ablation harness + per-experiment launchers
- `scripts/run/process-drone.ps1` — end-to-end drone photos to fused PLY
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
- SiftGPU is removed from the tree and the pipeline runs CPU SIFT. The
  verified Windows profile uses static `/MT` dependencies and has no
  GPL/LGPL-family DLLs in its runtime closure; the stale dynamic build is
  rejected by the packager. CUDA and Windows runtime prerequisites are listed
  in [`docs/runtime/README.md`](docs/runtime/README.md).

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

MMSP turns nadir drone photos into a fused dense point cloud (`dense/fused.ply`); V1 stops there (meshing, texturing and orthomosaics are non-goals). `colmap/` is a vendored COLMAP fork (upstream base `bd1fcf6`); engine work lives in `colmap/src/colmap/mvs/` plus its option plumbing. The only GPU ever run is a GeForce MX150 2 GB (`sm_61`); builds can also emit `sm_86`, which has been compiled but never run.

Read first: `AGENTS.md` (scope, success metric, license, Windows notes), `CONTRIBUTING.md` (workflow contract) and `MODS.md` (plan, verdicts, benchmark ledger; Indonesian, append-only). `colmap/AGENTS.md` is the upstream COLMAP guide (module layers, naming, ctest names). Docs can be stale; trust the files.

## Commands

Windows only (MSVC, CUDA 12.x, vcpkg, Ninja). Run from the repo root. Scripts are validated on both Windows PowerShell 5.1 and PowerShell 7.

```powershell
# one-time: machine paths (gitignored); MMSP_CUDA_HOME / MMSP_PRIMARY_ROOT / MMSP_SECONDARY_ROOT also work
Copy-Item env.local.example.ps1 env.local.ps1

# configure + build the engine (default build dir: colmap/build-mx150-final; ninja.exe on PATH or -NinjaExe)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup/configure-mx150.ps1 [-CudaArchitectures '61;86'] [-BuildDirectory <name>]
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup/build-mx150.ps1 [-BuildDirectory <name>]

# photos -> dense/fused.ply + run-summary.json (OutputDir: new or empty, outside the repo)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run/process-drone.ps1 -ImagesPath <photos> -OutputDir <out> [-ColmapExe <colmap.exe>] [-GpuIndex 0]

# dense-stage ablation on the frozen harness; -ExtraArgs replaces baseline flags of the same name
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run/run-ablate.ps1 -Label <name> -ExtraArgs '--PatchMatchStereo.<flag> <value>'

# point-cloud metrics (coverage, C2C, outliers); dependency-free C++17
cl /O2 /std:c++17 tools\metrics.cpp
tools\metrics.exe <ours.ply> <reference.ply> --pgm <holemap-prefix>

# standalone runtime package (RuntimeDir: new or empty, outside the repo); see docs/runtime/README.md
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup/package-runtime.ps1 -RuntimeDir <folder>
```

There is no single test command. The checks that exist:

```powershell
powershell -NoProfile -File tools/parsecheck.ps1 <script.ps1>   # must print errors=0; run it for every changed .ps1, on 5.1 and pwsh
powershell -NoProfile -File scripts/run/test-process-drone.ps1   # fake-COLMAP contract test of process-drone.ps1; also run with pwsh
bash security/scan-tests.sh                                      # secret/path scanner regression tests
git config core.hooksPath .githooks                              # once per clone: pre-commit / pre-push security scans
```

- C++ tests (GTest via `ctest`, names like `mvs/fusion_test`) are not built by the scripts: `configure-mx150.ps1` hardcodes `-DTESTS_ENABLED=OFF`. Running them needs a separate hand-configured build dir with `-DTESTS_ENABLED=ON` (not scripted, not verified here). No unit test covers `patch_match.cc` or `patch_match_cuda.cu`; kernel changes are judged by `run-ablate.ps1` plus `metrics.exe` numbers.
- Format C++ with `colmap/scripts/format/c++.sh` (uses `colmap/.clang-format`).

## Architecture

**Pipeline.** `scripts/run/process-drone.ps1` drives the `colmap` CLI through `feature_extractor` (CPU SIFT, 2048 px, single camera) → `sequential_matcher` (overlap 10) → `mapper` → `model_analyzer` → `image_undistorter` (700 px; it also rewrites `stereo/patch-match.cfg` so `__auto__, N` becomes 8) → `patch_match_stereo` → `stereo_fusion`. The tuned dense values (`window_step 2`, `num_iterations 1`, `pyramid_levels 1`, `filter_min_confidence 0.2`, `max_triangulation_angle 65`, `fuse_prior_weight 1.0`, …) are passed explicitly there; per MODS.md the MMSP flags default to upstream behavior in code. CPU SIFT/matching/mapping is the production path; `-NativeGpuSift` is an opt-in experiment that gave no end-to-end gain (MODS.md).

**Process contract.** Each stage prints `MMSP_STAGE_EVENT <json>` (`schemaVersion`, `stage`, `status` = started/completed/failed, `timestampUtc`); `completed` is emitted only after the stage output validates. `run-summary.json` carries `schemaVersion: 1` and `fusedCloudPath: "dense/fused.ply"`; a failed run exits nonzero with `status: "failed"`. External callers parse this and `test-process-drone.ps1` pins it, so keep it backward compatible.

**Engine (`colmap/src/colmap/mvs/`).** CMake builds `colmap_mvs` (CPU: depth/normal maps, workspace, fusion, meshing) and, only with `CUDA_ENABLED`, `colmap_mvs_cuda` (`patch_match.cc` with view selection and `PatchMatchController`, `patch_match_cuda.cu`, `gpu_mat_*`). Adding an MVS option is a vertical slice across files; skip a step and the flag or behavior is missing:

1. field in `patch_match_options.h` (default = upstream behavior);
2. `PrintOption` and `Check` in `patch_match_options.cc`;
3. `AddDefaultOption("PatchMatchStereo.<name>", …)` in `controllers/option_manager.cc` (fusion options use `StereoFusion.<name>`, in `fusion.{h,cc}`); without it there is no CLI flag;
4. the consumer in `patch_match.cc`, `patch_match_cuda.cu` or `fusion.cc`.

MMSP's additions so far: `max_triangulation_angle`, `single_pass`, `pyramid_levels`, `filter_min_confidence`, `StereoFusion.fuse_prior_weight`.

The sweep kernels run one thread per column with `SWEEP_THREADS_PER_BLOCK = 64` (element-wise kernels stay at 32: 64×64 exceeds 1024 threads per block) and ping-pong buffers via `Rotate()`. MODS.md declares micro-CUDA tuning exhausted; the remaining gap to OpenMVS is algorithmic (adaptive NCC window, coarse-to-fine, concurrent instances).

**Build profile.** vcpkg `x64-windows-static` with `/MT`; PoseLib and Faiss are fetched with pinned SHA-256 hashes (stale `FETCHCONTENT_SOURCE_DIR_*` overrides are cleared on configure); GUI, CGAL, LSD, ONNX, tests and IPO are off. Ceres has no SuiteSparse (GPL), so BA uses `DENSE_SCHUR`/`EIGEN_SPARSE` under `CERES_NO_SUITESPARSE` (`bundle_adjustment_ceres.cc`); `SPARSE_SCHUR` with `EIGEN_SPARSE` crashed the mapper. SiftGPU and LSD were deleted from the tree; don't reintroduce them. `package-runtime.ps1` audits the executable's DLL closure against an explicit license map, and an unknown DLL fails packaging.

## Gotchas

- `scripts/env.ps1` defaults `$ColmapExe` to `colmap/build-mx150/src/colmap/exe/colmap.exe`, but the configure/build scripts default to `build-mx150-final`. Set `$ColmapExe` in `env.local.ps1` (sourced after the default) or pass `-ColmapExe` (`process-drone.ps1` reads `env.ps1` only when it is omitted). The old `build-mx150` cache points at another checkout and the packager rejects it.
- `run-ablate.ps1` reuses `$PrimaryRoot/dense700`. Per CONTRIBUTING.md each run first moves `depth_maps/*.bin` and `normal_maps/*.bin` into `backup_pre_<label>/`, because both share file names.
- Committed files must hold no secrets, absolute local paths (Windows profile/drive/UNC, unix home) or data artifacts (photos, point clouds, databases, models, archives, binary blobs). `security/scan.sh` (gitleaks 8.30.1 via `GITLEAKS_BIN`) enforces this in the hooks and the CI `security` job. Use placeholders like `<cuda-toolkit>`, as MODS.md does; datasets, outputs and build dirs stay outside the repo.
- The CI `security` job runs on both `push` and `pull_request`. After a force-push (amend or rebase of an open PR branch) the `push` run fails closed with `invalid Git revision input`, because `github.event.before` is a commit the runner no longer has; a re-run does not help, and the `pull_request` run still reports the real result. Prefer a follow-up commit over amend plus force-push on an open PR.
- Benchmarks use two sites: primary (117 DJI nadir photos, `$PrimaryRoot`) and secondary (51 photos, `$SecondaryRoot`). Kernel rounds have been gated on no point loss versus the current champion; record the verdict with numbers in MODS.md before follow-up work.

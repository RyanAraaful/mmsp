# Task 4 Report — Confidence floor + fuse prior weight (CPU-side only)

Status: DONE (build green, no run — controller runs ablations). No commit (per brief).

## Step 0 — RED (old binary, before any production code)

```
E20261011 ... base_option_manager.cc:265] Failed to parse options - unrecognised option '--PatchMatchStereo.filter_min_confidence'.  EXIT=1
E20261011 ... base_option_manager.cc:265] Failed to parse options - unrecognised option '--StereoFusion.fuse_prior_weight'.        EXIT=1
```

(Note: first attempt without CUDA `PATH` failed with `0xC0000135` DLL launch error — not a valid RED; re-ran with `<cuda-toolkit>\cuda-env\bin` on PATH like `run-ablate.ps1` does.)
Bad-behavior record to beat: baseline 819,366 pts / 20.9 min, flat areas holed (tri65: 886,854 pts / 15.4 min).

## Step 1 — Reject invariants (read before implementing)

Depth filter (`patch_match_cuda.cu`, last sweep only, `SweepFromTopToBottom:1209-1276`):
- Per-view pass requires triangulation angle + incident angle OK, then branch on template params: photo-only (`sel_prob >= min_ncc_prob`), geom-only (reproj cost `<= filter_geom_consistency_max_cost`), or both.
- Pixel dies at `:1267` `num_consistent < filter_min_num_consistent` → depth/normal zeroed + consistency_mask cleared. `sel_prob_map` for the current row is valid at filter time (same pattern as `:1235`).
- Existing thresholds untouched by design.

Fusion (`fusion.cc:369-559`): traversal accumulates consistent pixels; point dies at `:528` `num_pixels < min_num_pixels`. Bounding-box/normal/median logic after that untouched.

## Step 2 — Minimal implementation (default-off, ≤20 core lines/side)

Depth side (`filter_min_confidence`, double, default 0 = dead code):
- `patch_match_options.h`: field + one-line why-comment. `.cc`: Print + Check (`0 <= v <= 1`, sel_prob range).
- `patch_match_cuda.cu`: `SweepOptions.filter_min_confidence` + 1 plumb line + rescue block: if the count test fails AND floor > 0, keep the pixel when `max(sel_prob over views) >= floor` (fmaxf loop, reuses the `:1235` read pattern).
- Core diff: ~11 kernel lines + field + plumb.

Fusion side (`fuse_prior_weight`, double, default 0 = identical):
- `fusion.h/.cc`: field + Print + Check (`>= 0`); `Fuse:527-528` acceptance becomes `num_pixels + fuse_prior_weight >= min_num_pixels` (fractional virtual support).
- Core diff: 3 lines.

Registration (`option_manager.cc`, actual name confirmed `AddStereoFusionOptions` as brief guessed):
- `PatchMatchStereo.filter_min_confidence` after `filter_geom_consistency_max_cost`; `StereoFusion.fuse_prior_weight` after `check_num_images`.

## Step 3 — BUILD

`build-mx150.ps1` exit 0 (15/15, colmap.exe relinked; only pre-existing style warnings, e.g. double→float conversions also present upstream). Pre-build: no `colmap` process (lock check clean).
GREEN parse check (new binary): `--help` lists `--PatchMatchStereo.filter_min_confidence arg (=0)` and `--StereoFusion.fuse_prior_weight arg (=0)`.

## Step 4 — Ready run commands (controller launches; one option at a time)

Depth first (small floor first):
```
powershell -NoProfile -ExecutionPolicy Bypass -File run-ablate.ps1 -Label conf02 -ExtraArgs '--PatchMatchStereo.filter_min_confidence 0.2'
```
Then, only if points rise without noise, fusion prior — HARNESS GAP: `run-ablate.ps1:55` fusion call takes no ExtraArgs, so either extend the harness with a fusion-args passthrough or run fusion manually, e.g.:
```
colmap.exe stereo_fusion --workspace_path <primary-dataset>\dense700 --workspace_format COLMAP --input_type geometric --output_path <primary-dataset>\dense700\fused_prior05.ply --StereoFusion.max_image_size 700 --StereoFusion.min_num_pixels 3 --StereoFusion.max_reproj_error 4.0 --StereoFusion.max_depth_error 0.05 --StereoFusion.max_normal_error 20.0 --StereoFusion.check_num_images 30 --StereoFusion.cache_size 4 --StereoFusion.fuse_prior_weight 0.5
```
Pass criteria: points > tri65 886,854 with no new visual noise on roof/vegetation screenshots; any noise = revert that option. Suggested ladder: conf 0.2 → 0.4; prior 0.5 → 1.0. Determinism: double-run point count within ±0.1%.

## Step 5 — Ledger (no commit)

Touched ONLY: `mvs/patch_match_options.h/.cc`, `mvs/patch_match_cuda.cu`, `mvs/fusion.h/.cc`, `controllers/option_manager.cc`. Other dirty files in `git status` are prior tasks'/build-fix work, not mine. Nothing committed.

## Skipped / risks

- No GPU run (per brief); default-off parity (defaults reproduce upstream bit-for-bit) unverified — first `conf02` run's control should be a default-flags rerun if tri65 maps are stale.
- `best_prob = max over views` rescue is lenient by design (single strong view rescues); if it admits noise, tighten to mean-of-top-2 rather than reverting the whole option.
- `fuse_prior_weight` has no upper-bound Check; values ≥ min_num_pixels accept single-pixel points — keep ladder ≤ 1.0 with harness `min_num_pixels 3`.
- Viewpoint oracle SKIP (no renderer on box), per brief.

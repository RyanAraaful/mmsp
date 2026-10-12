# Task 5 report — overlap I/O-komputasi: SKIP (idle overlappable 3.9% < 5%)

Status: **SKIP — no code written, no build, no commit.** Step 1 (measurement + code-location proof) IS the RED; it does not reproduce an overlappable idle ≥5%, so per brief + ponytail, NO CODE is the correct answer.

## 1. Method (no code, log only)

Source: `<primary-dataset>/log_patch_tri65.txt` (pyramid1/tri65 full-117 run, UTF-16LE, 13811 clean lines), parsed with PowerShell timestamp diffs (same-day, no midnight wrap). Denominator: `timer.cc:90 Elapsed time: 14.380 [minutes]` = **862.8 s**. No `colmap` process running during analysis; nothing built, launched, or committed. Working tree left untouched.

## 2. Numbers

| Window (summed over 234 problems = 2 passes × 117) | Total | % of 862.8 s |
|---|---|---|
| `Reading inputs...` → first `Sweep 1:` (brief's literal idle def, upper bound incl. GPU setup) | 84.51 s (pass0 14.49 s, avg 123.9 ms/view; pass1 70.02 s, avg 598.4 ms/view; max 1.081 s) | **9.80%** |
| Pure disk reads: `Reading inputs...` → `PatchMatch::Problem` print | 11.42 s (pass0 1.29 s @11.1 ms/view; pass1 10.13 s @86.6 ms/view) | **1.32%** |
| GPU-side setup remainder (allocs/HtoD/InitWorkspaceMemory, single-GPU critical path) | 73.09 s | 8.47% |
| Map writes (`patch_match.cc:673` → next view), gross | 44.87 s | 5.20% |
| minus inter-pass gap (last coarse write 23:44:55.039 → pass-1 view 1 23:45:17.503 = 22.46 s of `UpsamplePyramidSeeds` CPU + workspace rebuild, not per-view write I/O) | −22.46 s | −2.60% |
| True per-view writes ≈ 22.4 s | ≈22.4 s | ≈2.6% |
| **Disk I/O actually overlappable (reads + true writes)** | **≈33.8 s** | **≈3.9% < 5% (threshold = 43.14 s)** |
| GPU sweeps (`Total:` lines, 234×) | 791.5 s | 91.7% → run is compute-bound |

Worked example (pass-1 view 1): read 0.358 s → prints ~1 ms → `PatchMatch::Run` → `Initialization: 0.0290 s` → ~0.45 s unlogged allocs/HtoD/init → `Sweep 1`. Disk ≈ 40%, GPU setup ≈ 60% of that view's 0.84 s window.

## 3. Code-location proof (RED, `colmap/src/colmap/mvs/patch_match.cc`)

- `:240` `thread_pool_ = make_unique<ThreadPool>(gpu_indices_.size())`, log shows `gpu_index: 0` → **exactly 1 worker** (all 234 views ran on tid 3708, strictly sequential `read → compute → write`). There is zero inter-view concurrency today — no lock held during compute to relieve.
- `:600-665` `workspace_mutex_` is locked **only around the read section** and released at `:665`, **before** `PatchMatch::Run` (`:670-671`). I/O is not "mutex-locked during compute"; the pipeline is sequential by single-thread construction.
- `:241-242` + `:648-662` `io_thread_pool_` **already parallelizes intra-view reads** across CPU threads — that is why pure disk I/O is only 11–87 ms/view. The cheap rung of the ladder is already taken.
- Therefore the brief's Step-2 design (prefetch next-view inputs in `io_thread_pool_` during sweeps) prizes **at most 11.42 s = 1.32%**. Even adding an async writer (≈22.4 s, needs new thread + `DepthMap`/`NormalMap` lifetime management — not "region kecil"), the ceiling is ≈3.9% < 5%. The remaining ≈8.5% is GPU setup on the single MX150's critical path; overlapping it needs CUDA-stream/HtoD surgery in `PatchMatchCuda` — out of scope, VRAM-risky on 2 GB, determinism-risky — for a single-digit prize on a 91.7%-compute-bound run.

## 4. Decision: SKIP

No Step 2/3. No file touched, no build (Windows-lock rule respected anyway — no run was active), no commit. Determinism/VRAM impact: none (no change). Note the literal 9.80% upper bound exceeds 5% only because it counts non-overlappable GPU setup; the decomposition above shows the overlappable subset is 3.9%.

## 5. What would reopen this

Revisit only if a future mod makes per-view disk I/O ≥5% (e.g. larger `max_image_size`, slower disk, or network workspace) — re-run this Step-1 recipe on the new log first. The 22.46 s inter-pass `UpsamplePyramidSeeds` CPU gap is a separate (non-I/O-overlap) pipelining opportunity, ≈2.6% alone — also below bar, noted for Task 7, not pursued here.

## 6. context7

**Not used.** No CUDA API (stream/event/pinned memory) was touched — no code was written at all — so there was nothing to resolve docs for. Mandatory-only-if-touching-CUDA condition did not trigger.

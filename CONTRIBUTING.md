# Contributing to MMSP

Thanks for your interest in contributing to MMSP (Multi-view Mapping &
Stereo Processing), a drone-oriented photogrammetry engine covering the
pipeline from photos to dense point cloud. This document is the contract
for every contribution; please read it before opening an issue or pull
request. The project source of truth for plans and benchmark evidence is
`MODS.md`.

## Ways to contribute

- **Code**: kernel work in `colmap/src/colmap/mvs/` and its option
  plumbing, the harness in `scripts/`, or `tools/metrics.cpp`.
- **Benchmarks**: ablation runs on new datasets (same harness, same
  metrics, numbers first).
- **Docs**: corrections to `README.md`, `MODS.md`, or `docs/`.
- **Bug reports**: deterministic repros with logs (see below).

## Ground rules (non-negotiable)

1. **License purity** — never introduce GPL/AGPL/non-commercial code
   into the build or the runtime path, and never copy code from
   AGPL-licensed comparators (e.g. OpenMVS) into this tree. Ported ideas
   must be clean-room rewrites. SiftGPU is never executed.
2. **Scope first** — engine scope is `mvs/` plus its option plumbing.
   Touch a shared function only after grepping all of its callers, and
   fix root causes once in shared code. Out-of-scope areas (sparse SfM
   internals, meshing, GUI) need maintainer approval first.
3. **Evidence before claims** — performance or quality claims require
   measured numbers (benchmark logs, `metrics.exe` output), never
   guesses. If your investigation surfaces even one load-bearing issue,
   say so clearly instead of smoothing it over.
4. **No secrets, ever** — no API keys, tokens, passwords, private paths
   or credentials in code, logs, queries, or commits (see `.gitignore`).
   If you leak one, tell the maintainer immediately so it can be rotated.

## Development setup

- Windows + Visual Studio 2022 (MSVC 19.34+), CUDA toolkit 12.x with an
  `sm_61`-capable NVIDIA driver, vcpkg.
- Point `CUDA_PATH` / `CUDA_HOME` / `CUDAToolkit_ROOT` at your toolkit,
  put its `bin/` on `PATH` (`scripts/setup/configure-mx150.ps1` is an
  example), then build with the equivalent of
  `scripts/setup/build-mx150.ps1`.
- Never rebuild while a run is in progress (Windows locks the binary).

## Workflow for changes

1. **Ablations** go through the frozen harness
  (`scripts/run/run-ablate.ps1`) with a label. Every run moves
   `depth_maps/*.bin` + `normal_maps/*.bin` into a
   `backup_pre_<label>/` subdirectory first (both map types share file
   names — separate subdirectories are mandatory).
2. **Record the verdict in `MODS.md` with numbers first** (keep/reject +
   why) before any follow-up work. History of verdicts is the project's
   memory — do not rewrite it, append.
3. **Smallest complete diff** — no new dependency, abstraction, option,
   or config nobody asked for. Deletion beats addition. Mark known
   limits as `shortcut: <limit>, <when to upgrade>`.
4. **PowerShell lives in `.ps1` files** (never inline `$` in tooling),
   and every script must pass `tools/parsecheck.ps1`.
5. **C++ follows the existing conventions**: `PascalCase` types/methods,
   `snake_case_` members (trailing underscore), `snake_case` locals;
   format with the repo's clang-format config before submitting.

## Testing

- New non-trivial logic (a branch, loop, parser, numeric or GPU code)
  needs a check that fails before the fix and passes after
 (red-green). Trivial changes need none.
- Run the relevant existing checks (`ctest` for touched C++ modules
  where available) and quote their output as evidence in your PR.
- Benchmarks must report: configuration flags, wall time, point count,
  output hash, and `metrics.exe` numbers (coverage, C2C, outlier) for
  both benchmark sites where applicable.

## Commit messages and pull requests

- **Atomic commits**: upstream baseline, kernel work, scripts, and docs
  in separate commits. One logical change per commit.
- Message format: short imperative summary (≤ 72 chars), e.g.
  `sweep: raise thread block to 64 for occupancy`. Explain the *why* in
  the body when it is not obvious; reference `MODS.md` verdicts.
- Push rebased, reviewable history (no merge commits on `main`).
- PR description must include: what changed and why, evidence
 (numbers/logs), what was skipped or not checked, and risks the
  reviewer must know. A PR without evidence is not reviewable.

## Reporting issues

Include: GPU model + driver + CUDA toolkit, exact command/flags,
relevant `log_*.txt` excerpts, output hash if applicable, and what you
expected vs what happened. "It got slower" without numbers will be sent
back for numbers.

## Security

Do not post secrets or private data in issues, PRs, or commits. For
suspected vulnerabilities, open a minimal issue without exploit details
and the maintainer will follow up.

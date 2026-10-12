# MMSP — agent instructions (read every session)

Source of truth: `MODS.md` (plan, decisions, metrics) + `CONTRIBUTING.md`
(workflow contract). Docs may be stale after context compaction — trust
the files, not memory.

- Scope: SfM-to-dense engine, V1 ends at the fused dense point cloud.
  Default work area is `colmap/src/colmap/mvs/` plus its option plumbing;
  sparse internals, meshing, and GUI need approval first.
- Success metric: points/minute vs OpenMVS DensifyPointCloud with
  no-hole coverage, on every benchmark site. Claims only from measured
  numbers, never guesses.
- License: permissive-only tree (Apache-2.0, see `LICENSE` +
  `THIRD_PARTY_NOTICES.md`). No GPL/AGPL/non-commercial code in build
  or runtime. GPU feature extraction is removed; SfM always CPU SIFT.
- Windows notes: never rebuild while a run uses the binary (file lock);
  PowerShell goes in `.ps1` files; validate scripts with
  `tools/parsecheck.ps1`.

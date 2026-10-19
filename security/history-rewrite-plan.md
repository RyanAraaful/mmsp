# History rewrite plan (privacy)

Status: **not required.** No personal machine paths were found in reachable
history; MMSP history is preserved as-is.

## Evidence (2026-10-19, pinned gitleaks 8.30.1)

- Full-history scan with `.gitleaks.toml` (custom user-profile and
  unix/macOS-home rules, `--log-opts=--all`): **0 findings**.
- Pickaxe searches across all refs for the local user-profile prefix, the
  checkout-root prefixes (slash/backslash spellings) and pilot temp roots:
  0 commits each.
- Current tree: `security/scan.sh tree` is clean; the same check runs in CI
  via `.github/workflows/security.yml` on every push and pull request.

The only profile-like path in the tree is the GitHub macOS-runner home
`/Users/runner/...` inside the bundled upstream COLMAP workflow
(`colmap/.github/workflows/build-pycolmap.yml`). It is runner-generated, not
personal, is treated as an allowed CI-runner path by the scanner allowlist,
and upstream files were not modified.

## Decision

- No `git-filter-repo` run is scheduled for MMSP.
- History hygiene from here on is enforced by the pre-commit/pre-push hooks
  (`.githooks/`, opt-in per clone) and the CI `security` workflow.
- If a future full-history scan reports findings, follow the procedure
  recorded in Riltra's `security/history-rewrite-plan.md`: mirror clone,
  `git-filter-repo --replace-text` with the same placeholder scheme,
  verification, owner-approved force-push, GitHub Support purge.

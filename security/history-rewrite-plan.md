# History rewrite plan (privacy)

Status: **required under the expanded scanner, not executed.** No rewrite and
no force-push were performed. Execution is owner-gated (see "Execution").

The earlier version of this plan said "not required". That conclusion came
from the profile-only rule set. The absolute-workspace-path rule added in the
scanner correction round changes the historical findings, so this plan is
superseded and must not be cited as a clean-history result.

Post-merge state (2026-10-20, after PR #2) was re-measured with the final
`.gitleaks.toml`; the current numbers, refs and open items are recorded in
"Verified current state" below. The 2026-10-19 measurements in this document
are kept as the historical record of that round.

## Verified current state (2026-10-20, after the PR #2 squash merge)

Method: pinned gitleaks 8.30.1 (local SHA-256 checked against the published
release checksums), this repository's `.gitleaks.toml`, `git log -p --all`,
and no `.gitleaksignore`. Reproduce with:

    gitleaks git --config .gitleaks.toml --redact --no-banner \
      --log-opts="--all" --gitleaks-ignore-path=<empty-dir> .

| Item | Value |
| --- | --- |
| Full-history findings | 368 in 4 commits, 90 files |
| Rule mix | 368 `local-absolute-path` |
| Credential-rule findings | 0 |
| Remote branches | 2 (`main`, `security/privacy-remediation`) |
| Commits reachable from all refs | 51 |
| Pull refs | `refs/pull/1/head` (PR #1, closed), `refs/pull/2/head` (PR #2, merged) |
| Tags / notes | none |
| DCO sign-off lines | 8 across 51 commits (43 pre-security commits carry none) |
| `main` tip | `2b1bf42` (PR #2 squash) |
| Scanner regression suite | 32 passed, 0 failed |

Difference against the 2026-10-19 measurement below: `0d9f706` is no longer
an ancestor of `main` (PR #2 was squash-merged), so its two synthetic fixture
findings are no longer reported; the branch `security/privacy-remediation`
still contains that commit. Neither measurement contains a credential
finding.

The two `.gitleaksignore` entries are currently **inert**: the new-branch
scan (`d62f06a..afb6708`) exits 0 with the file removed as well as with it,
and the history scan reports no finding in
`security/testdata/allowed/drive-paths.txt`. Removing the file is a separate,
owner-approved change; it stays documented as temporary here.

## Evidence (2026-10-19, pinned gitleaks 8.30.1)

- Full-history scan with the final `.gitleaks.toml` (`--log-opts=--all`),
  measured 2026-10-19: **370 findings in 5 commits, 91 files**. The
  2026-10-20 re-measurement above gives 368 in 4 commits and 90 files; the
  difference is the synthetic fixture finding in `0d9f706`, which the final
  config no longer reports.
- Rule mix: 370 `local-absolute-path`; zero credential-rule findings.
- Categories: local development-checkout prefixes (358 findings), dataset and
  tool-install drive paths, and two synthetic fixture paths. Exact literal
  values are deliberately not committed.
- Current tree: `security/scan.sh tree` is clean and
  `security/scan-tests.sh` passes 32/32 (measured locally and in CI run
  39303929702); CI runs both on every push and pull request.

Affected commits as measured on 2026-10-19. The 2026-10-20 re-measurement
covers the same 4 commits with the same per-commit counts; `0d9f706` is no
longer reported.

| Commit | Date | Subject | Findings | Files |
| --- | --- | --- | --- | --- |
| `2e20230` | 2026-10-12 | scripts/: run/measure/setup layout + absolute path refs updated | 287 | 287 scripts |
| `e1acf86` | 2026-10-12 | project docs (MODS/AGENTS/SDD), metrics.cpp tool, run configs | 55 | 48 docs, `MODS.md`, `drone-mx150.ini` |
| `e55936f` | 2026-10-12 | docs: flatten docs/superpowers/* to docs/{plans,specs,sdd} | 17 | 9 docs, 8 scripts |
| `ba51cfc` | 2026-10-12 | license: purge SiftGPU (UNC) + LSD (AGPL) dirs | 9 | 9 scripts |
| `0d9f706` | 2026-10-19 | feat(security): add gitleaks scan with hooks and CI workflow | 2 | old synthetic allowed-fixture file |

Both branches still contain affected commits: `main` carries four of the five
(`0d9f706` was squashed away by PR #2) and `security/privacy-remediation`
carries all five. The two findings in `0d9f706` were the old synthetic
allowed-fixture example under `security/testdata/allowed/drive-paths.txt`, not
personal data; under the final config the scanner no longer reports them, so
the replacement-list decision for that literal is moot and the post-rewrite
scan stays clean without it.

Until the rewrite lands, `.gitleaksignore` still pins those two fingerprints,
but the pins are inert: the new-branch scan (`d62f06a..afb6708`) exits 0 with
the file removed as well as with it. The entries remain temporary: remove and
re-evaluate them after the rewrite, when the full-history scan must be clean
without them.

## Replacement scheme

Mirror the Riltra scheme with MMSP-specific roots:

| Placeholder | Replaces |
| --- | --- |
| `<USER_HOME>` | local Windows user-profile prefix, all slash/JSON spellings |
| `<MMSP_REPO_ROOT>` | local checkout root, all spellings |
| `<DATASET_ROOT>` | local dataset root(s) |
| `<TOOLS_ROOT>` | local tool-install root(s) |
| `<EXAMPLE_ROOT>` | synthetic fixture example |

The exact literal list is not committed; it lives in the private remediation
workspace. `git-filter-repo --replace-text` applies it to every reachable
commit.

## Upstream scope

COLMAP sources are vendored in this repository; there is no upstream git
history here. The full scan covered 46 commits across all refs (48 commits in
`rev-list --all`; merge commits without diffs are skipped); the current
baseline is 51 commits. A rewrite affects
only MMSP's own commits. It does not modify engine, CUDA, benchmark, dataset
or upstream COLMAP source content, except where a historical script or config
blob embeds a local path string; those strings are replaced with placeholders.
No upstream sync is part of this plan.

## Dry-run status

No dry-run was executed in the scanner-correction round; the owner instruction
for that round prohibited running `git-filter-repo`. Before execution, run the
same procedure recorded in Riltra's `security/history-rewrite-plan.md` on an
isolated `--mirror` clone, with this literal list, and record:

- commit count before/after and rewritten count;
- per-branch tip mapping;
- full-history scan = 0 findings under the final config;
- DCO sign-off count unchanged;
- subject and author metadata unchanged.

The mirror dry-run must also cover the scanner's mode gap: a history scan
(`gitleaks git`) reports no finding in
`security/testdata/allowed/drive-paths.txt`, while a file scan of the same
content (`gitleaks dir`) reports two. A clean history scan is therefore not
sufficient evidence on its own; the literal grep in the verification list is
mandatory, not optional.

## Impact on refs, PRs, DCO and evidence

- Refs today: `main` and `security/privacy-remediation`; no tags or notes.
  Re-check immediately before execution.
- Two pull requests exist now (PR #1 closed, PR #2 merged), and the remote
  exposes `refs/pull/1/head` and `refs/pull/2/head`; the PR ref caveat is
  therefore smaller than Riltra's but forks/clones can still retain old
  objects.
- DCO: 8 sign-off lines currently (51 commits; the 43 pre-security commits
  carry none, because this repository had no DCO convention before the
  security work). Sign-offs are commit-message text and survive. No commit is
  cryptographically signed (`%G?` is `N` for all); a signed commit added later
  must be re-signed after a rewrite.
- Any document that pins an MMSP commit SHA or cites evidence by commit
  coordinate becomes stale. Check `docs/` before execution and update the
  owner-facing notes, not historical measurement values. Checked on
  2026-10-20: no file under `docs/` cites `2e20230`, `e1acf86`, `e55936f`,
  `ba51cfc` or `0d9f706`, so no coordinate in this repository has to change.
- Backups and benchmark evidence hashes are unaffected inside the current
  tree; do not alter historical results while updating coordinates.

## GitHub Support purge is not guaranteed

The exposure is local filesystem layout, not credentials. GitHub Support may
decline or partially action a purge for path-only content, and unreferenced
objects, caches, logs, forks and existing clones can retain old bytes. A
rewrite reduces reachable exposure; it cannot guarantee erasure. Record this
residual risk in the owner decision.

## Recontamination risks

- A stale clone (pre-rewrite history) that pushes afterwards reintroduces the
  old blobs. Keep the backup mirror read-only.
- Local branches, worktrees and forks that are not reset keep the old objects.
- CI caches and artifacts may contain old evidence archives; review and purge
  them if the exposure matters.
- The current tree must stay clean: hooks are opt-in per clone, CI is the
  backstop.

## Verification (must pass after the real run)

1. `security/scan.sh range <root>..HEAD` on both branches = clean.
2. Full-history scan with the final `.gitleaks.toml` = 0 findings.
3. Case-insensitive grep over all reachable trees for the replaced literals =
   0 hits.
4. `git rev-list --all --count` unchanged; DCO sign-off count unchanged.
5. `bash security/scan-tests.sh` passes 32/32 on a fresh clone.
6. `git ls-remote origin` shows no unexpected surviving refs.
7. File-level spot check of the known path-bearing files at their pre-rewrite
   SHAs (`gitleaks dir`), because the history scan does not report the
   synthetic fixture paths that a file scan does.

## Execution (owner-gated)

`main` has no ruleset and no classic branch protection, so the force-push step
below is technically possible; it stays owner-gated because it discards the
published history and its pull-request refs.

1. Freeze pushes; back up a bare mirror outside the repository.
2. Run pinned `git-filter-repo --replace-text <full list> --force` on the
   mirror; re-add `origin`; verify per the list above.
3. Force-push `main` and `security/privacy-remediation` explicitly.
4. Re-clone locally (or `reset --hard` every branch) and remove stale
   worktrees.
5. Contact GitHub Support to purge unreferenced objects; accept that
   path-only exposure may not be fully purged.
6. Re-run CI and confirm the `security` job passes.

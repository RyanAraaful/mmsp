# History rewrite plan (privacy)

Status: **required under the expanded scanner, not executed.** No rewrite and
no force-push were performed. Execution is owner-gated (see "Execution").

The earlier version of this plan said "not required". That conclusion came
from the profile-only rule set. The absolute-workspace-path rule added in the
scanner correction round changes the historical findings, so this plan is
superseded and must not be cited as a clean-history result.

## Evidence (2026-10-19, pinned gitleaks 8.30.1)

- Full-history scan with the final `.gitleaks.toml` (`--log-opts=--all`):
  **370 findings in 5 commits, 91 files**.
- Rule mix: 370 `local-absolute-path`; zero credential-rule findings.
- Categories: local development-checkout prefixes (358 findings), dataset and
  tool-install drive paths, and two synthetic fixture paths. Exact literal
  values are deliberately not committed.
- Current tree: `security/scan.sh tree` is clean and
  `security/scan-tests.sh` passes 23/23; CI runs both on every push and pull
  request.

| Commit | Date | Subject | Findings | Files |
| --- | --- | --- | --- | --- |
| `2e20230` | 2026-10-12 | scripts/: run/measure/setup layout + absolute path refs updated | 287 | 287 scripts |
| `e1acf86` | 2026-10-12 | project docs (MODS/AGENTS/SDD), metrics.cpp tool, run configs | 55 | 48 docs, `MODS.md`, `drone-mx150.ini` |
| `e55936f` | 2026-10-12 | docs: flatten docs/superpowers/* to docs/{plans,specs,sdd} | 17 | 9 docs, 8 scripts |
| `ba51cfc` | 2026-10-12 | license: purge SiftGPU (UNC) + LSD (AGPL) dirs | 9 | 9 scripts |
| `0d9f706` | 2026-10-19 | feat(security): add gitleaks scan with hooks and CI workflow | 2 | old synthetic allowed-fixture file |

Both branches (`main` and `security/privacy-remediation`) contain affected
commits. The two findings in `0d9f706` are the old synthetic allowed-fixture
example under `security/testdata/allowed/drive-paths.txt`, not personal data;
replace that literal in the rewrite so the post-rewrite scan is clean.

Until the rewrite lands, those two findings are pinned by fingerprint in
`.gitleaksignore` so new-branch merge-base scans pass without allowlisting the
path or the rule. The entries are temporary: remove and re-evaluate them after
the rewrite, when the full-history scan must be clean without them.

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
`rev-list --all`; merge commits without diffs are skipped). A rewrite affects
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

## Impact on refs, PRs, DCO and evidence

- Refs today: `main` and `security/privacy-remediation`; no tags, notes or
  pull refs. Re-check immediately before execution.
- No MMSP pull requests exist and the remote exposes no `refs/pull/*`; the PR
  ref caveat is therefore smaller than Riltra's but forks/clones can still
  retain old objects.
- DCO: 5 sign-off lines currently; sign-offs are commit-message text and
  survive. No commit is cryptographically signed (`%G?` is `N` for all); a
  signed commit added later must be re-signed after a rewrite.
- Any document that pins an MMSP commit SHA or cites evidence by commit
  coordinate becomes stale. Check `docs/` before execution and update the
  owner-facing notes, not historical measurement values.
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
5. `bash security/scan-tests.sh` passes 23/23 on a fresh clone.
6. `git ls-remote origin` shows no unexpected surviving refs.

## Execution (owner-gated)

1. Freeze pushes; back up a bare mirror outside the repository.
2. Run pinned `git-filter-repo --replace-text <full list> --force` on the
   mirror; re-add `origin`; verify per the list above.
3. Force-push `main` and `security/privacy-remediation` explicitly.
4. Re-clone locally (or `reset --hard` every branch) and remove stale
   worktrees.
5. Contact GitHub Support to purge unreferenced objects; accept that
   path-only exposure may not be fully purged.
6. Re-run CI and confirm the `security` job passes.

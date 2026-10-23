#!/usr/bin/env bash
# Regression tests for security/scan.sh and .gitleaks.toml.
# Usage: bash security/scan-tests.sh
# Requires: git, tar, and gitleaks 8.30.1 (via GITLEAKS_BIN or PATH).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
SCAN="$HERE/scan.sh"
TD="$HERE/testdata"
DEFAULT_BRANCH=main
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0
# Synthetic trigger values are assembled at runtime so this script itself stays
# clean for the scanner it tests (the raw fixtures live in security/testdata).
SYN_P1="ghp_"
SYN_P2="aB3xK9qW2mZ7pL4vN8cR1sD6fG5hJ0kT2eYz"
TOKEN_VALUE="${SYN_P1}${SYN_P2}"
TEST_USER="alice"
ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

case_dir() { # fixture -> fresh temp dir containing it
  d="$(mktemp -d "$TMP/case-XXXXXX")"
  mkdir -p "$d/fixture"
  cp "$1" "$d/fixture/"
  printf '%s' "$d"
}

expect_code() { # label expected_exit fixture
  label="$1"; want="$2"; fixture="$3"
  d="$(case_dir "$fixture")"
  "$SCAN" dir "$d" >"$TMP/$label.out" 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then ok "$label"; else no "$label (want exit $want, got $got)"; fi
}

# 1-5: blocked fixtures must be detected
expect_code "win-user-path blocked" 1 "$TD/blocked/win-user-path.txt"
expect_code "win-user-path alt-slash blocked" 1 "$TD/blocked/win-user-path-alt-slash.txt"
expect_code "win-user-path json-escaped blocked" 1 "$TD/blocked/win-user-path-json.txt"
expect_code "unix-home-path blocked" 1 "$TD/blocked/unix-home-path.txt"
expect_code "synthetic token blocked" 1 "$TD/blocked/synthetic-token.txt"

# absolute workspace paths outside user profiles must be detected
expect_code "local drive path blocked" 1 "$TD/blocked/local-drive-path.txt"
expect_code "local drive path alt-slash blocked" 1 "$TD/blocked/local-drive-path-alt-slash.txt"
expect_code "local drive path json-escaped blocked" 1 "$TD/blocked/local-drive-path-json.txt"
expect_code "UNC path blocked" 1 "$TD/blocked/unc-path.txt"

# 6-8: allowed fixtures must pass
expect_code "relative path allowed" 0 "$TD/allowed/relative-path.txt"
expect_code "env placeholders allowed" 0 "$TD/allowed/env-placeholders.txt"
expect_code "system and runner paths allowed" 0 "$TD/allowed/drive-paths.txt"

# 9: scanner output must not contain the secret value
d="$(case_dir "$TD/blocked/synthetic-token.txt")"
"$SCAN" dir "$d" >"$TMP/redact.out" 2>&1
got=$?
if [ "$got" -eq 1 ] && ! grep -qF "$TOKEN_VALUE" "$TMP/redact.out"; then
  ok "scanner output redacts secrets"
else
  no "scanner output redacts secrets (exit $got; see $TMP/redact.out)"
fi

# 10: missing scanner fails closed with exit 3
d="$(case_dir "$TD/allowed/relative-path.txt")"
GITLEAKS_BIN="$TMP/definitely-missing" "$SCAN" dir "$d" >"$TMP/missing.out" 2>&1
got=$?
if [ "$got" -eq 3 ]; then ok "missing scanner fails closed (exit 3)"; else no "missing scanner fails closed (want exit 3, got $got)"; fi

# 11: committed file matching .gitignore is still scanned
repo="$TMP/git-case"
mkdir -p "$repo"
git -C "$repo" init -q
printf 'secret-data.txt\n' >"$repo/.gitignore"
printf 'C:/Users/%s/leak.txt\n' "$TEST_USER" >"$repo/secret-data.txt"
git -C "$repo" add .gitignore secret-data.txt -f
git -C "$repo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "add tracked-but-ignored file"
( cd "$repo" && "$SCAN" tree ) >"$TMP/ignored.out" 2>&1
got=$?
if [ "$got" -eq 1 ]; then ok "committed-but-ignored file is scanned"; else no "committed-but-ignored file is scanned (want exit 1, got $got)"; fi

# 12: staged changes are scanned before commit
printf '/home/%s/staged-leak.txt\n' "$TEST_USER" >"$repo/staged-leak.txt"
git -C "$repo" add staged-leak.txt
( cd "$repo" && "$SCAN" staged ) >"$TMP/staged.out" 2>&1
got=$?
if [ "$got" -eq 1 ]; then ok "staged leak is blocked"; else no "staged leak is blocked (want exit 1, got $got)"; fi

# 13: newly staged artifact paths and binary content are blocked, while source text is allowed.
artifactrepo="$TMP/artifact-case"
mkdir -p "$artifactrepo"
git -C "$artifactrepo" init -q
printf 'clean\n' >"$artifactrepo/README.md"
git -C "$artifactrepo" add README.md
git -C "$artifactrepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "clean artifact-test base"
expect_staged_result() { # label path expected_exit [binary]
  label="$1"; path="$2"; want="$3"; kind="${4:-text}"
  mkdir -p "$artifactrepo/$(dirname "$path")"
  if [ "$kind" = binary ]; then printf '\211PNG\r\n\032\n\000synthetic-only' >"$artifactrepo/$path"
  elif [ "$kind" = jpeg-signature ]; then printf '\377\330\377synthetic-only' >"$artifactrepo/$path"
  elif [ "$kind" = nul-tail ]; then
    printf 'synthetic text line\n%.0s' {1..8192} >"$artifactrepo/$path"
    printf '\000' >>"$artifactrepo/$path"
  else printf 'synthetic test text only\n' >"$artifactrepo/$path"; fi
  git -C "$artifactrepo" add -- "$path"
  ( cd "$artifactrepo" && "$SCAN" staged ) >"$TMP/$label.out" 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then ok "$label"; else no "$label (want exit $want, got $got)"; fi
  git -C "$artifactrepo" reset -q -- "$path"
  rm -f -- "$artifactrepo/$path"
  rmdir "$artifactrepo/$(dirname "$path")" 2>/dev/null || true
}
expect_staged_result "staged photo extension blocked" "synthetic-photo.jpg" 1
expect_staged_result "staged survey path blocked" "survey/trajectory.txt" 1
expect_staged_result "staged disguised binary blocked" "synthetic-payload.txt" 1 binary
expect_staged_result "staged disguised photo signature blocked" "jpeg-signature.txt" 1 jpeg-signature
expect_staged_result "staged trailing NUL after long text blocked" "nul-tail.txt" 1 nul-tail
expect_staged_result "staged source text allowed" "src/example.cpp" 0

# New destinations from rename/copy are additions and must pass the same guard.
git -C "$artifactrepo" mv README.md renamed-photo.png
( cd "$artifactrepo" && "$SCAN" staged ) >"$TMP/renamed-artifact.out" 2>&1
got=$?
if [ "$got" -eq 1 ]; then ok "renamed artifact destination is blocked"; else no "renamed artifact destination is blocked (want exit 1, got $got)"; fi
git -C "$artifactrepo" reset -q -- .
git -C "$artifactrepo" checkout -q -- README.md
rm -f "$artifactrepo/renamed-photo.png"
cp "$artifactrepo/README.md" "$artifactrepo/copied-model.onnx"
git -C "$artifactrepo" add copied-model.onnx
( cd "$artifactrepo" && "$SCAN" staged ) >"$TMP/copied-artifact.out" 2>&1
got=$?
if [ "$got" -eq 1 ]; then ok "copied artifact destination is blocked"; else no "copied artifact destination is blocked (want exit 1, got $got)"; fi
git -C "$artifactrepo" reset -q -- copied-model.onnx
rm -f "$artifactrepo/copied-model.onnx"

# Hooks are exercised in isolated repositories with local-only remotes.
prepare_hook_repo() { # path pre-commit|pre-push
  hookrepo="$1"; hookkind="$2"
  mkdir -p "$hookrepo/.githooks" "$hookrepo/security"
  cp "$SCAN" "$hookrepo/security/scan.sh"
  cp "$ROOT/.gitleaks.toml" "$hookrepo/.gitleaks.toml"
  if [ "$hookkind" = pre-commit ]; then cp "$ROOT/.githooks/pre-commit" "$hookrepo/.githooks/pre-commit"; fi
  if [ "$hookkind" = pre-push ]; then cp "$ROOT/.githooks/pre-push" "$hookrepo/.githooks/pre-push"; fi
  chmod +x "$hookrepo/security/scan.sh" "$hookrepo/.githooks/"*
  git -C "$hookrepo" init -q -b main
  git -C "$hookrepo" config user.name scan-test
  git -C "$hookrepo" config user.email scan-test@example.invalid
  git -C "$hookrepo" config core.hooksPath .githooks
  printf 'clean\n' >"$hookrepo/README.md"
  git -C "$hookrepo" add README.md .githooks security/scan.sh .gitleaks.toml
  git -C "$hookrepo" commit -q -m "clean hook-test base"
}

hookrepo="$TMP/pre-commit-hook-case"
prepare_hook_repo "$hookrepo" pre-commit
hooks_path="$(git -C "$hookrepo" config --local --get core.hooksPath)"
if [ "$hooks_path" = .githooks ]; then ok "pre-commit hook path is active"; else no "pre-commit hook path is active"; fi
expect_hook_commit_block() { # label path kind
  label="$1"; path="$2"; kind="$3"
  mkdir -p "$hookrepo/$(dirname "$path")"
  case "$kind" in
    path) cp "$TD/blocked/local-drive-path.txt" "$hookrepo/$path" ;;
    token) printf '%s' "$TOKEN_VALUE" >"$hookrepo/$path" ;;
    artifact) printf 'synthetic test text only\n' >"$hookrepo/$path" ;;
  esac
  git -C "$hookrepo" add -- "$path"
  before="$(git -C "$hookrepo" rev-parse HEAD)"
  if [ "$kind" = path ]; then git -C "$hookrepo" commit -q -m "$label" >"$TMP/hook-$kind.out" 2>&1
  elif [ "$kind" = token ]; then git -C "$hookrepo" commit -q -m "$label" >"$TMP/hook-$kind.out" 2>&1
  else git -C "$hookrepo" commit -q -m "$label" >"$TMP/hook-$kind.out" 2>&1
  fi
  got=$?
  after="$(git -C "$hookrepo" rev-parse HEAD)"
  if [ "$got" -ne 0 ] && [ "$before" = "$after" ]; then ok "$label"; else no "$label (hook did not block)"; fi
  git -C "$hookrepo" reset -q -- "$path"
  rm -f -- "$hookrepo/$path"
  rmdir "$hookrepo/$(dirname "$path")" 2>/dev/null || true
}
expect_hook_commit_block "pre-commit blocks synthetic local path" "path-leak.txt" path
expect_hook_commit_block "pre-commit blocks synthetic token" "token-leak.txt" token
expect_hook_commit_block "pre-commit blocks synthetic image" "synthetic.png" artifact
printf 'clean\n' >"$hookrepo/scanner-unavailable.txt"
git -C "$hookrepo" add scanner-unavailable.txt
before="$(git -C "$hookrepo" rev-parse HEAD)"
GITLEAKS_BIN="$TMP/missing-scanner" git -C "$hookrepo" commit -q -m "scanner unavailable must block" >"$TMP/hook-missing-scanner.out" 2>&1
got=$?
after="$(git -C "$hookrepo" rev-parse HEAD)"
if [ "$got" -ne 0 ] && [ "$before" = "$after" ]; then ok "pre-commit fails closed without scanner"; else no "pre-commit fails closed without scanner"; fi
git -C "$hookrepo" reset -q -- scanner-unavailable.txt
rm -f "$hookrepo/scanner-unavailable.txt"

pushhookrepo="$TMP/pre-push-hook-case"
pushremote="$TMP/pre-push-local-remote.git"
prepare_hook_repo "$pushhookrepo" pre-push
git init -q --bare "$pushremote"
git -C "$pushhookrepo" remote add origin "$pushremote"
git -C "$pushhookrepo" push -q -u origin main >"$TMP/pre-push-clean.out" 2>&1
got=$?
base_push="$(git --git-dir="$pushremote" rev-parse refs/heads/main 2>/dev/null)"
if [ "$got" -eq 0 ]; then ok "pre-push allows a clean local push"; else no "pre-push allows a clean local push"; fi
printf 'synthetic artifact placeholder\n' >"$pushhookrepo/synthetic-cloud.ply"
git -C "$pushhookrepo" add synthetic-cloud.ply
git -C "$pushhookrepo" commit -q -m "synthetic artifact for pre-push test"
git -C "$pushhookrepo" push origin main >"$TMP/pre-push-artifact.out" 2>&1
got=$?
after_push="$(git --git-dir="$pushremote" rev-parse refs/heads/main 2>/dev/null)"
if [ "$got" -ne 0 ] && [ "$base_push" = "$after_push" ]; then ok "pre-push blocks artifact before local remote update"; else no "pre-push blocks artifact before local remote update"; fi
git -C "$pushhookrepo" checkout -q -b scanner-unavailable "$base_push"
printf 'clean\n' >"$pushhookrepo/scanner-unavailable.txt"
git -C "$pushhookrepo" add scanner-unavailable.txt
git -C "$pushhookrepo" commit -q -m "scanner unavailable pre-push test"
GITLEAKS_BIN="$TMP/missing-scanner" git -C "$pushhookrepo" push -u origin scanner-unavailable >"$TMP/pre-push-missing-scanner.out" 2>&1
got=$?
remote_missing_branch=0;git --git-dir="$pushremote" show-ref --verify --quiet refs/heads/scanner-unavailable || remote_missing_branch=$?
if [ "$got" -ne 0 ] && [ "$remote_missing_branch" -ne 0 ]; then ok "pre-push fails closed without scanner"; else no "pre-push fails closed without scanner"; fi

# Range and new-branch CI modes enforce the same artifact policy.
rangeartifact="$TMP/artifact-range-case"
mkdir -p "$rangeartifact"
git -C "$rangeartifact" init -q
printf 'clean\n' >"$rangeartifact/README.md"
git -C "$rangeartifact" add README.md
git -C "$rangeartifact" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "clean range base"
rangebase="$(git -C "$rangeartifact" rev-parse HEAD)"
printf 'synthetic result placeholder\n' >"$rangeartifact/survey-results.csv"
git -C "$rangeartifact" add survey-results.csv
git -C "$rangeartifact" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "synthetic range artifact"
rangehead="$(git -C "$rangeartifact" rev-parse HEAD)"
( cd "$rangeartifact" && "$SCAN" range "$rangebase..$rangehead" ) >"$TMP/range-artifact.out" 2>&1
got=$?
if [ "$got" -eq 1 ]; then ok "range blocks a newly added survey artifact"; else no "range blocks a newly added survey artifact (want exit 1, got $got)"; fi

# A merge result can add a file that exists in neither parent, so compare it
# with its first parent and exercise the pre-push hook against a local remote.
mergerepo="$TMP/artifact-merge-case"
mergeremote="$TMP/artifact-merge-local-remote.git"
prepare_hook_repo "$mergerepo" pre-push
mergebase="$(git -C "$mergerepo" rev-parse HEAD)"
git init --bare -q "$mergeremote"
git -C "$mergerepo" remote add origin "$mergeremote"
git -C "$mergerepo" push -q origin main >"$TMP/merge-baseline-push.out" 2>&1
got=$?
if [ "$got" -eq 0 ]; then ok "pre-push allows the clean merge-test baseline"; else no "pre-push allows the clean merge-test baseline (got $got)"; fi
git -C "$mergerepo" checkout -q -b topic
printf 'topic edit\n' >"$mergerepo/README.md"
git -C "$mergerepo" add README.md
git -C "$mergerepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "topic edit"
git -C "$mergerepo" checkout -q main
printf 'main edit\n' >"$mergerepo/README.md"
git -C "$mergerepo" add README.md
git -C "$mergerepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "main edit"
git -C "$mergerepo" merge --no-commit topic >"$TMP/merge-conflict.out" 2>&1 || true
printf 'resolved merge\n' >"$mergerepo/README.md"
printf 'synthetic merge-only artifact\n' >"$mergerepo/cloud.ply"
git -C "$mergerepo" add README.md cloud.ply
git -C "$mergerepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "merge adds synthetic artifact"
mergehead="$(git -C "$mergerepo" rev-parse HEAD)"
merge_parent_count="$(git -C "$mergerepo" rev-list --parents -n 1 "$mergehead" | awk '{print NF - 1}')"
if [ "$merge_parent_count" -eq 2 ]; then ok "merge fixture is a two-parent commit"; else no "merge fixture is a two-parent commit"; fi
( cd "$mergerepo" && "$SCAN" range "$mergebase..$mergehead" ) >"$TMP/merge-range.out" 2>&1
got=$?
if [ "$got" -eq 1 ]; then ok "range blocks an artifact added only by a merge commit"; else no "range blocks an artifact added only by a merge commit (want exit 1, got $got)"; fi
git -C "$mergerepo" push origin main >"$TMP/merge-pre-push.out" 2>&1
got=$?
merge_remote_after="$(git --git-dir="$mergeremote" rev-parse refs/heads/main 2>/dev/null)"
if [ "$got" -ne 0 ] && [ "$mergebase" = "$merge_remote_after" ]; then ok "pre-push blocks an artifact added only by a merge commit"; else no "pre-push blocks an artifact added only by a merge commit"; fi

# Root commits are compared with Git's empty tree.
rootrepo="$TMP/root-artifact-hook-case"
rootremote="$TMP/root-artifact-local-remote.git"
mkdir -p "$rootrepo/.githooks" "$rootrepo/security"
git -C "$rootrepo" init -q -b main
git -C "$rootrepo" config user.name scan-test
git -C "$rootrepo" config user.email scan-test@example.invalid
git -C "$rootrepo" config core.hooksPath .githooks
cp "$SCAN" "$rootrepo/security/scan.sh"
cp "$ROOT/.gitleaks.toml" "$rootrepo/.gitleaks.toml"
cp "$ROOT/.githooks/pre-push" "$rootrepo/.githooks/pre-push"
chmod +x "$rootrepo/security/scan.sh" "$rootrepo/.githooks/pre-push"
printf 'synthetic root artifact\n' >"$rootrepo/root-cloud.ply"
git -C "$rootrepo" add root-cloud.ply .githooks security/scan.sh .gitleaks.toml
git -C "$rootrepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "root artifact fixture"
git init --bare -q "$rootremote"
git -C "$rootrepo" remote add origin "$rootremote"
git -C "$rootrepo" push -u origin main >"$TMP/root-pre-push.out" 2>&1
got=$?
root_remote_missing=0;git --git-dir="$rootremote" show-ref --verify --quiet refs/heads/main || root_remote_missing=$?
if [ "$got" -ne 0 ] && [ "$root_remote_missing" -ne 0 ]; then ok "pre-push blocks an artifact in a root commit"; else no "pre-push blocks an artifact in a root commit"; fi

newartifact="$TMP/artifact-new-branch-case"
mkdir -p "$newartifact"
git -C "$newartifact" init -q
printf 'clean\n' >"$newartifact/README.md"
git -C "$newartifact" add README.md
git -C "$newartifact" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "clean new-branch base"
newbase="$(git -C "$newartifact" rev-parse HEAD)"
git -C "$newartifact" update-ref refs/remotes/origin/main "$newbase"
git -C "$newartifact" checkout -q -b feature
printf 'synthetic model placeholder\n' >"$newartifact/model-output.pth"
git -C "$newartifact" add model-output.pth
git -C "$newartifact" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "synthetic new-branch artifact"
( cd "$newartifact" && "$SCAN" new-branch main ) >"$TMP/newbranch-artifact.out" 2>&1
got=$?
if [ "$got" -eq 1 ]; then ok "new branch blocks a newly added model artifact"; else no "new branch blocks a newly added model artifact (want exit 1, got $got)"; fi

( cd "$rangeartifact" && "$SCAN" range no-such-range ) >"$TMP/range-invalid.out" 2>&1
got=$?
if [ "$got" -eq 4 ]; then ok "invalid Git range fails closed"; else no "invalid Git range fails closed (want exit 4, got $got)"; fi
printf 'malformed input\n' | ( cd "$rangeartifact" && "$SCAN" outgoing ) >"$TMP/outgoing-invalid.out" 2>&1
got=$?
if [ "$got" -eq 4 ]; then ok "malformed pre-push input fails closed"; else no "malformed pre-push input fails closed (want exit 4, got $got)"; fi

# allowlists are per fixture file, not per directory: a new file under
# security/testdata is still scanned even though the known fixtures are allowed
SCANNER="${GITLEAKS_BIN:-gitleaks}"
( cd "$ROOT" && "$SCANNER" dir --config "$ROOT/.gitleaks.toml" --redact --no-banner security/testdata ) >"$TMP/testdata-scan.out" 2>&1
got=$?
if [ "$got" -eq 0 ]; then ok "known fixtures are allowlisted by exact path"; else no "known fixtures are allowlisted by exact path (want exit 0, got $got; see $TMP/testdata-scan.out)"; fi

unlisted="$TD/blocked/zz-unlisted-leak.txt"
printf 'C:/Users/%s/unlisted-leak.txt\n' "$TEST_USER" >"$unlisted"
( cd "$ROOT" && "$SCANNER" dir --config "$ROOT/.gitleaks.toml" --redact --no-banner security/testdata ) >"$TMP/unlisted.out" 2>&1
got=$?
rm -f "$unlisted"
if [ "$got" -eq 1 ]; then ok "unlisted file under security/testdata is detected"; else no "unlisted file under security/testdata is detected (want exit 1, got $got; see $TMP/unlisted.out)"; fi

# push (outgoing) and range modes detect leaks in commit history
pushrepo="$TMP/push-case"
mkdir -p "$pushrepo"
git -C "$pushrepo" init -q
printf 'clean\n' >"$pushrepo/README.md"
git -C "$pushrepo" add README.md
git -C "$pushrepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "clean base"
base=$(git -C "$pushrepo" rev-parse HEAD)
cp "$TD/blocked/local-drive-path.txt" "$pushrepo/push-leak.txt"
git -C "$pushrepo" add push-leak.txt
git -C "$pushrepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "leak"
leak=$(git -C "$pushrepo" rev-parse HEAD)

printf 'refs/heads/main %s refs/heads/main %s\n' "$base" "0000000000000000000000000000000000000000" | ( cd "$pushrepo" && "$SCAN" outgoing ) >"$TMP/outgoing-clean.out" 2>&1
got=$?
if [ "$got" -eq 0 ]; then ok "outgoing clean commits pass"; else no "outgoing clean commits pass (want exit 0, got $got)"; fi

printf 'refs/heads/main %s refs/heads/main %s\n' "$leak" "0000000000000000000000000000000000000000" | ( cd "$pushrepo" && "$SCAN" outgoing ) >"$TMP/outgoing-leak.out" 2>&1
got=$?
if [ "$got" -eq 1 ]; then ok "outgoing leak is blocked"; else no "outgoing leak is blocked (want exit 1, got $got)"; fi

( cd "$pushrepo" && "$SCAN" range "$base..$leak" ) >"$TMP/range-leak.out" 2>&1
got=$?
if [ "$got" -eq 1 ]; then ok "range leak is blocked"; else no "range leak is blocked (want exit 1, got $got)"; fi

( cd "$pushrepo" && "$SCAN" range "$leak..$leak" ) >"$TMP/range-empty.out" 2>&1
got=$?
if [ "$got" -eq 0 ]; then ok "empty range passes"; else no "empty range passes (want exit 0, got $got)"; fi

# 13: this repository's committed tree is clean
( cd "$ROOT" && "$SCAN" tree ) >"$TMP/tree.out" 2>&1
got=$?
if [ "$got" -eq 0 ]; then ok "repository tree is clean"; else no "repository tree is clean (want exit 0, got $got; see $TMP/tree.out)"; fi

# New-branch pushes scan only commits introduced after the merge-base with the
# default branch; an unavailable default ref or merge-base fails closed.
nbrepo="$TMP/newbranch-case"
mkdir -p "$nbrepo"
git -C "$nbrepo" init -q
printf 'clean\n' >"$nbrepo/README.md"
git -C "$nbrepo" add README.md
git -C "$nbrepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "clean base"
cp "$TD/blocked/local-drive-path.txt" "$nbrepo/default-leak.txt"
git -C "$nbrepo" add default-leak.txt
git -C "$nbrepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "historical leak on default branch"
git -C "$nbrepo" update-ref refs/remotes/origin/main "$(git -C "$nbrepo" rev-parse HEAD)"
git -C "$nbrepo" checkout -q -b feature
printf 'clean\n' >"$nbrepo/feature.txt"
git -C "$nbrepo" add feature.txt
git -C "$nbrepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "clean feature commit"

( cd "$nbrepo" && "$SCAN" new-branch main ) >"$TMP/newbranch-clean.out" 2>&1
got=$?
if [ "$got" -eq 0 ]; then ok "new branch passes when the only leak predates the merge-base"; else no "new branch passes when the only leak predates the merge-base (want exit 0, got $got; see $TMP/newbranch-clean.out)"; fi

cp "$TD/blocked/local-drive-path.txt" "$nbrepo/own-leak.txt"
git -C "$nbrepo" add own-leak.txt
git -C "$nbrepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "introduce leak"
( cd "$nbrepo" && "$SCAN" new-branch main ) >"$TMP/newbranch-leak.out" 2>&1
got=$?
if [ "$got" -eq 1 ]; then ok "new branch blocks a leak it introduces"; else no "new branch blocks a leak it introduces (want exit 1, got $got)"; fi

noref="$TMP/newbranch-noref"
mkdir -p "$noref"
git -C "$noref" init -q
printf 'clean\n' >"$noref/README.md"
git -C "$noref" add README.md
git -C "$noref" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "clean base"
( cd "$noref" && "$SCAN" new-branch main ) >"$TMP/newbranch-noref.out" 2>&1
got=$?
if [ "$got" -eq 4 ] && grep -q "fail-closed" "$TMP/newbranch-noref.out"; then ok "new branch without the default ref fails closed"; else no "new branch without the default ref fails closed (want exit 4 with fail-closed message, got $got; see $TMP/newbranch-noref.out)"; fi

first_branch="$(git -C "$noref" symbolic-ref --short HEAD)"
git -C "$noref" checkout -q --orphan unrelated
printf 'other\n' >"$noref/other.txt"
git -C "$noref" add other.txt
git -C "$noref" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "unrelated root"
git -C "$noref" update-ref refs/remotes/origin/main "$(git -C "$noref" rev-parse HEAD)"
git -C "$noref" checkout -q "$first_branch"
( cd "$noref" && "$SCAN" new-branch main ) >"$TMP/newbranch-unrelated.out" 2>&1
got=$?
if [ "$got" -eq 4 ] && grep -q "merge-base" "$TMP/newbranch-unrelated.out"; then ok "new branch without a merge-base fails closed"; else no "new branch without a merge-base fails closed (want exit 4 with merge-base message, got $got; see $TMP/newbranch-unrelated.out)"; fi

# Fingerprint ignores are exact: the synthetic historical finding is ignored,
# while similar content or a new path is still detected.
ignrepo="$TMP/ignore-case"
mkdir -p "$ignrepo/security/testdata/allowed"
git -C "$ignrepo" init -q
printf 'clean\n' >"$ignrepo/README.md"
git -C "$ignrepo" add README.md
git -C "$ignrepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "clean base"
ignbase="$(git -C "$ignrepo" rev-parse HEAD)"
cp "$TD/blocked/local-drive-path.txt" "$ignrepo/security/testdata/allowed/drive-paths.txt"
git -C "$ignrepo" add security/testdata/allowed/drive-paths.txt
git -C "$ignrepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "historical synthetic finding"
hist="$(git -C "$ignrepo" rev-parse HEAD)"
( cd "$ignrepo" && "$SCAN" range "$ignbase..$hist" ) >"$TMP/ignore-red.out" 2>&1
got=$?
if [ "$got" -eq 1 ]; then ok "historical synthetic finding fails without an ignore fingerprint"; else no "historical synthetic finding fails without an ignore fingerprint (want exit 1, got $got)"; fi

printf '%s\n' "$hist:security/testdata/allowed/drive-paths.txt:local-absolute-path:2" >"$ignrepo/.gitleaksignore"
( cd "$ignrepo" && "$SCAN" range "$ignbase..$hist" ) >"$TMP/ignore-green.out" 2>&1
got=$?
if [ "$got" -eq 0 ]; then ok "exact fingerprint ignores the historical synthetic finding"; else no "exact fingerprint ignores the historical synthetic finding (want exit 0, got $got; see $TMP/ignore-green.out)"; fi

cp "$TD/blocked/local-drive-path.txt" "$ignrepo/security/testdata/allowed/drive-paths-copy.txt"
git -C "$ignrepo" add security/testdata/allowed/drive-paths-copy.txt
git -C "$ignrepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "same content, new path"
( cd "$ignrepo" && "$SCAN" range "$ignbase..HEAD" ) >"$TMP/ignore-path.out" 2>&1
got=$?
if [ "$got" -eq 1 ]; then ok "similar content at a new path stays blocked"; else no "similar content at a new path stays blocked (want exit 1, got $got)"; fi

git -C "$ignrepo" rm -q security/testdata/allowed/drive-paths-copy.txt
cp "$TD/blocked/local-drive-path-alt-slash.txt" "$ignrepo/security/testdata/allowed/drive-paths.txt"
git -C "$ignrepo" add security/testdata/allowed/drive-paths.txt
git -C "$ignrepo" -c user.name=scan-test -c user.email=scan-test@example.invalid -c commit.gpgsign=false commit -q -m "new content in the ignored file"
( cd "$ignrepo" && "$SCAN" range "$ignbase..HEAD" ) >"$TMP/ignore-content.out" 2>&1
got=$?
if [ "$got" -eq 1 ]; then ok "new content in the ignored file stays blocked"; else no "new content in the ignored file stays blocked (want exit 1, got $got)"; fi

# The two historical synthetic findings pinned in .gitleaksignore must not fail
# the real branch range scan.
( cd "$ROOT" && "$SCAN" new-branch "$DEFAULT_BRANCH" ) >"$TMP/historical-range.out" 2>&1
got=$?
if [ "$got" -eq 0 ]; then ok "documented historical findings do not fail the new-branch scan"; else no "documented historical findings do not fail the new-branch scan (want exit 0, got $got; see $TMP/historical-range.out)"; fi

echo
echo "scan-tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

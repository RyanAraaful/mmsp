#!/usr/bin/env bash
# Secret / local-path scan entry point for this repository (pinned: gitleaks 8.30.1).
#
# Modes:
#   tree               scan the committed tree of HEAD
#   range <revrange>   scan commits in a git revision range (e.g. base..head)
#   new-branch <base>  scan commits a new branch introduced (merge-base..HEAD)
#   staged             scan staged changes (pre-commit hook)
#   outgoing           scan commits being pushed, read from pre-push stdin (+ tip trees)
#   dir <path>         scan an arbitrary directory
#
# Environment:
#   GITLEAKS_BIN     scanner binary (default: gitleaks from PATH)
#   GITLEAKS_CONFIG  config file (default: <this script's repository>/.gitleaks.toml)
#
# Exit codes: 0 clean | 1 findings | 3 scanner unavailable | 4 usage/config/preflight error.
set -u
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${GITLEAKS_CONFIG:-$HERE/../.gitleaks.toml}"
GITLEAKS="${GITLEAKS_BIN:-gitleaks}"

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print } NR > 1 && !/^#/ { exit }' "$0"
  exit 4
}

if ! command -v "$GITLEAKS" >/dev/null 2>&1; then
  echo "scan: gitleaks not found: $GITLEAKS" >&2
  echo "scan: install pinned gitleaks 8.30.1 (see security/README.md) or set GITLEAKS_BIN." >&2
  exit 3
fi

if [ ! -f "$CONFIG" ]; then
  echo "scan: config not found: $CONFIG" >&2
  exit 4
fi

run_dir() { ( cd "$1" && "$GITLEAKS" dir --config "$CONFIG" --redact --no-banner . ); }
run_git() { "$GITLEAKS" git --config "$CONFIG" --redact --no-banner "$@" .; }

artifact_path_blocked() {
  local path="/${1,,}/"
  case "$path" in
    *.jpg/*|*.jpeg/*|*.png/*|*.tif/*|*.tiff/*|*.bmp/*|*.gif/*|*.webp/*|*.heic/*|*.heif/*|*.dng/*|*.mpo/*|*.mp4/*|*.mov/*|*.avi/*|\
    *.las/*|*.laz/*|*.ply/*|*.pcd/*|*.e57/*|*.xyz/*|*.pts/*|*.obj/*|\
    *.csv/*|*.tsv/*|*.gpx/*|*.kml/*|*.geojson/*|*.shp/*|*.shx/*|*.dbf/*|*.prj/*|*.gpkg/*|\
    *.db/*|*.sqlite/*|*.sqlite3/*|*.db3/*|*.bin/*|*.depth/*|*.normal/*|*.npy/*|*.npz/*|*.h5/*|*.hdf5/*|\
    *.zip/*|*.7z/*|*.rar/*|*.tar/*|*.tgz/*|*.gz/*|*.bz2/*|*.xz/*|*.zst/*|\
    *.onnx/*|*.pt/*|*.pth/*|*.ckpt/*|*.model/*|*.weights/*|*.safetensors/*|*.tflite/*|*.engine/*|\
    *.exe/*|*.dll/*|*.so/*|*.dylib/*|*.pyd/*|*.o/*|*.a/*|*.lib/*|*.whl/*)
      return 0 ;;
  esac
  case "$path" in
    */dataset/*|*/datasets/*|*/survey/*|*/surveys/*|*/pointcloud/*|*/point_cloud/*|*/point-cloud/*|\
    */photos/*|*/depth_maps/*|*/normal_maps/*|*/sparse_models/*|*/dense_models/*|\
    */reconstruction_outputs/*|*/processing_database/*|*/benchmark_outputs/*)
      return 0 ;;
  esac
  return 1
}

artifact_signature_blocked() {
  local signature
  signature="$( (set +o pipefail; git cat-file blob "$1" | od -An -N16 -tx1 2>/dev/null) | tr -d '[:space:]')"
  case "$signature" in
    ffd8ff*|89504e470d0a1a0a*|474946383761*|474946383961*|424d*|49492a00*|4d4d002a*|\
    504b0304*|504b0506*|377abcaf271c*|526172211a07*|1f8b*|425a68*|fd377a585a00*|28b52ffd*|\
    53514c69746520666f726d6174203300*|4c415346*|706c790a*|23504344*)
      return 0 ;;
  esac
  case "$signature" in
    52494646????????57454250*|????????66747970*) return 0 ;;
  esac
  return 1
}

check_changed_blob() {
  local path="$1" blob="$2" size nul_free_size
  if artifact_path_blocked "$path"; then
    echo "scan: blocked: changed path matches the dataset/processing artifact policy" >&2
    return 1
  fi
  if ! git cat-file -e "$blob^{blob}" >/dev/null 2>&1; then
    echo "scan: fail-closed: changed file object is unavailable" >&2
    return 4
  fi
  size="$(git cat-file -s "$blob" 2>/dev/null)" || {
    echo "scan: fail-closed: changed file size is unavailable" >&2
    return 4
  }
  case "$size" in ''|*[!0-9]*)
    echo "scan: fail-closed: invalid changed file size" >&2
    return 4 ;;
  esac
  [ "$size" -eq 0 ] && return 0
  if artifact_signature_blocked "$blob"; then
    echo "scan: blocked: changed file content matches a protected artifact signature" >&2
    return 1
  fi
  nul_free_size="$(set -o pipefail; git cat-file blob "$blob" | LC_ALL=C tr -d '\000' | wc -c)" 2>/dev/null || {
    echo "scan: fail-closed: could not inspect changed file content" >&2
    return 4
  }
  nul_free_size="${nul_free_size//[[:space:]]/}"
  case "$nul_free_size" in ''|*[!0-9]*)
    echo "scan: fail-closed: invalid text byte count" >&2
    return 4 ;;
  esac
  if [ "$nul_free_size" -ne "$size" ]; then
    echo "scan: blocked: changed file has binary content" >&2
    return 1
  fi
  return 0
}

scan_changed_paths() {
  local kind="$1" commit="${2:-}" raw header path old_mode new_mode old_blob new_blob status extra rc=0 parent
  local -a root_arg=() diff_args=()
  raw="$(mktemp)" || {
    echo "scan: fail-closed: could not create artifact scan input" >&2
    return 4
  }
  if [ "$kind" = staged ]; then
    if ! git diff --cached --raw -z --no-renames --diff-filter=AM >"$raw" 2>/dev/null; then
      rm -f "$raw"
      echo "scan: fail-closed: staged Git diff is invalid" >&2
      return 4
    fi
  else
    if parent="$(git rev-parse --verify "$commit^1" 2>/dev/null)"; then
      diff_args=("$parent" "$commit")
    else
      root_arg=(--root)
      diff_args=("$commit")
    fi
    if ! git diff-tree "${root_arg[@]}" --no-commit-id --raw -z --no-renames --diff-filter=AM -r "${diff_args[@]}" >"$raw" 2>/dev/null; then
      rm -f "$raw"
      echo "scan: fail-closed: commit tree diff is invalid" >&2
      return 4
    fi
  fi
  while IFS= read -r -d '' header; do
    if ! IFS= read -r -d '' path; then
      rc=4
      break
    fi
    old_mode=""; new_mode=""; old_blob=""; new_blob=""; status=""; extra=""
    IFS=' ' read -r old_mode new_mode old_blob new_blob status extra <<<"$header"
    if [ -n "$extra" ] || { [ "$status" != A ] && [ "$status" != M ]; } || [ -z "$new_blob" ]; then
      rc=4
      echo "scan: fail-closed: malformed Git diff record" >&2
      break
    fi
    check_changed_blob "$path" "$new_blob"
    rc=$?
    [ "$rc" -eq 0 ] || break
  done <"$raw"
  rm -f "$raw"
  return "$rc"
}

scan_added_commits() {
  local commits commit rc=0
  commits="$(mktemp)" || {
    echo "scan: fail-closed: could not create commit scan input" >&2
    return 4
  }
  if ! git rev-list "$@" >"$commits" 2>/dev/null; then
    rm -f "$commits"
    echo "scan: fail-closed: invalid Git revision input" >&2
    return 4
  fi
  while IFS= read -r commit; do
    if ! git cat-file -e "$commit^{commit}" >/dev/null 2>&1; then
      rc=4
      echo "scan: fail-closed: commit object is unavailable" >&2
      break
    fi
    scan_changed_paths commit "$commit"
    rc=$?
    [ "$rc" -eq 0 ] || break
  done <"$commits"
  rm -f "$commits"
  return "$rc"
}

mode="${1:-}"
[ -n "$mode" ] || usage
shift

case "$mode" in
  tree)
    d="$(mktemp -d)"
    trap 'rm -rf "$d"' EXIT
    git archive HEAD | tar -x -C "$d" || { echo "scan: git archive HEAD failed" >&2; exit 4; }
    run_dir "$d"
    ;;
  range)
    [ $# -eq 1 ] || usage
    scan_added_commits "$1"
    artifact_rc=$?
    [ "$artifact_rc" -eq 0 ] || exit "$artifact_rc"
    run_git --log-opts="$1"
    ;;
  new-branch)
    [ $# -eq 1 ] || usage
    base_ref="refs/remotes/origin/$1"
    if ! git rev-parse --verify --quiet "$base_ref" >/dev/null; then
      echo "scan: fail-closed: $base_ref is unavailable; fetch the default branch before scanning a new branch" >&2
      exit 4
    fi
    base="$(git merge-base HEAD "$base_ref")" || base=""
    if [ -z "$base" ]; then
      echo "scan: fail-closed: no merge-base between HEAD and $base_ref; refusing to scan unbounded history" >&2
      exit 4
    fi
    scan_added_commits "$base..HEAD"
    artifact_rc=$?
    [ "$artifact_rc" -eq 0 ] || exit "$artifact_rc"
    run_git --log-opts="$base..HEAD"
    ;;
  staged)
    run_git --staged
    scanner_rc=$?
    scan_changed_paths staged
    artifact_rc=$?
    [ "$artifact_rc" -eq 0 ] || exit "$artifact_rc"
    exit "$scanner_rc"
    ;;
  outgoing)
    line=""
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      [ -n "$line" ] || continue
      lref=""; lsha=""; rref=""; rsha=""; extra=""
      IFS=' ' read -r lref lsha rref rsha extra <<<"$line"
      if [ -z "$lref" ] || [ -z "$lsha" ] || [ -z "$rref" ] || [ -z "$rsha" ] || [ -n "$extra" ] || \
        ! git check-ref-format "$lref" >/dev/null 2>&1 || ! git check-ref-format "$rref" >/dev/null 2>&1; then
        echo "scan: fail-closed: malformed pre-push input" >&2
        exit 4
      fi
      if [[ ! "$lsha" =~ ^[[:xdigit:]]{40}$ && ! "$lsha" =~ ^[[:xdigit:]]{64}$ ]] || \
        [[ ! "$rsha" =~ ^[[:xdigit:]]{40}$ && ! "$rsha" =~ ^[[:xdigit:]]{64}$ ]]; then
        echo "scan: fail-closed: malformed pre-push object id" >&2
        exit 4
      fi
      if [[ "$lsha" =~ ^0{40}$ || "$lsha" =~ ^0{64}$ ]]; then continue; fi
      if ! git cat-file -e "$lsha^{commit}" >/dev/null 2>&1; then
        echo "scan: fail-closed: local push commit is unavailable" >&2
        exit 4
      fi
      if [[ "$rsha" =~ ^0{40}$ || "$rsha" =~ ^0{64}$ ]]; then
        scan_added_commits "$lsha" --not --remotes
        artifact_rc=$?
        [ "$artifact_rc" -eq 0 ] || exit "$artifact_rc"
        run_git --log-opts="$lsha --not --remotes" || exit $?
      else
        if ! git cat-file -e "$rsha^{commit}" >/dev/null 2>&1; then
          echo "scan: fail-closed: remote push base is unavailable locally" >&2
          exit 4
        fi
        scan_added_commits "$rsha..$lsha"
        artifact_rc=$?
        [ "$artifact_rc" -eq 0 ] || exit "$artifact_rc"
        run_git --log-opts="$rsha..$lsha" || exit $?
      fi
      d="$(mktemp -d)" || { echo "scan: fail-closed: could not create tip scan directory" >&2; exit 4; }
      if ! git archive "$lsha" | tar -x -C "$d"; then
        rm -rf "$d"
        echo "scan: fail-closed: pushed tip could not be archived" >&2
        exit 4
      fi
      run_dir "$d"
      tree_rc=$?
      rm -rf "$d"
      [ "$tree_rc" -eq 0 ] || exit "$tree_rc"
    done
    exit 0
    ;;
  dir)
    [ $# -eq 1 ] || usage
    run_dir "$1"
    ;;
  *)
    usage
    ;;
esac

rc=$?
exit "$rc"

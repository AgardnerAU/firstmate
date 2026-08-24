#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/fm-wake-lib.sh"

BRANCH_ROWS="$STATE/.branch-eligible-rows"
MAIN_ROWS="$STATE/.main-eligible-rows"
TMP=
LOCK_HELD=false

cleanup() {
  local status=$?
  [ -z "$TMP" ] || rm -f -- "$TMP" 2>/dev/null || true
  [ "$LOCK_HELD" = false ] || fm_lock_release "$FM_WAKE_QUEUE_LOCK"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

rows_valid() {
  [ -s "$1" ] && awk 'BEGIN { ok=1 } !/^[0-9]+$/ || seen[$0]++ { ok=0 } END { exit !ok }' "$1"
}

case "${1:-}" in
  publish)
    shift
    [ "$#" -gt 0 ] || exit 2
    TMP=$(mktemp "$STATE/.branch-eligible-rows.tmp.XXXXXX") || exit 1
    printf '%s\n' "$@" > "$TMP" || exit 1
    chmod 0600 "$TMP" || exit 1
    rows_valid "$TMP" || exit 2
    fm_lock_acquire_wait "$FM_WAKE_QUEUE_LOCK"
    LOCK_HELD=true
    replace=1
    if [ -e "$BRANCH_ROWS" ] || [ -L "$BRANCH_ROWS" ]; then
      rows_valid "$BRANCH_ROWS" && cmp -s "$TMP" "$BRANCH_ROWS" || exit 1
      replace=0
    fi
    rows_valid "$TMP" || exit 1
    awk -F '\t' -v requested="$TMP" -v main="$MAIN_ROWS" '
      BEGIN {
        while ((getline line < requested) > 0) wanted[line]=1
        while ((getline line < main) > 0) owned[line]=1
      }
      NF >= 5 && $2 ~ /^[0-9]+$/ && $2 in wanted { present[$2]=1 }
      END {
        for (seq in wanted) if (seq in owned) exit 3
        for (seq in wanted) if (!(seq in present)) exit 1
      }
    ' "$FM_WAKE_QUEUE"
    rc=$?
    [ "$rc" -eq 0 ] || exit "$rc"
    if [ "$replace" -eq 1 ]; then
      _fm_atomic_replace "$TMP" "$BRANCH_ROWS" || exit 1
      TMP=
    fi
    ;;
  release)
    [ "$#" -eq 1 ] || exit 2
    fm_lock_acquire_wait "$FM_WAKE_QUEUE_LOCK"
    LOCK_HELD=true
    rm -f -- "$BRANCH_ROWS" || exit 1
    ;;
  *)
    echo "usage: fm-wake-grant.sh publish SEQUENCE... | release" >&2
    exit 2
    ;;
esac

fm_lock_release "$FM_WAKE_QUEUE_LOCK"
LOCK_HELD=false
exit 0

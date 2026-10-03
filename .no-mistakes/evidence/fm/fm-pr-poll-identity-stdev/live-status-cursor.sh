#!/usr/bin/env bash
# Live driver: real bin/fm-wake-drain.sh presents a task's status log in a
# disposable lab home, the state volume is "renumbered" (the identity reader
# seam reports the file's REAL inode and birth time with a new st_dev, as APFS
# does after a reboot), a new status line is appended, and the drain runs
# again. Run once on the change (HEAD) and once on the base commit.
set -u
WT=$PWD
run_case() {  # <label> <bin-root>
  local label=$1 root=$2 LAB dev
  LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
  env -u NO_MISTAKES_GATE -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE "$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
  cat > "$LAB/reader" <<'SH'
#!/usr/bin/env bash
i=$(/usr/bin/stat -f %i "$1") || exit 1; b=$(/usr/bin/stat -f %FB "$1")
printf 'strong:%s:%s:%s' "$(cat "$FM_LAB_DEV")" "$i" "$b"
SH
  chmod +x "$LAB/reader"; dev=$(/usr/bin/stat -f %d "$LAB/state"); echo "$dev" > "$LAB/dev"
  drain() { env -u NO_MISTAKES_GATE -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE FM_HOME="$LAB" FM_LAB_DEV="$LAB/dev" FM_STATUS_IDENTITY_READER="$LAB/reader" "$root/bin/fm-wake-drain.sh" 2>/dev/null | grep 'remount'; }
  echo "=== $label"
  printf 'note: settled history before the reboot\n' > "$LAB/state/remount.status"
  echo "--- drain 1 (st_dev=$dev):"; drain
  echo "$((dev+2))" > "$LAB/dev"
  printf 'note: first event after the reboot\n' >> "$LAB/state/remount.status"
  echo "--- drain 2 after renumber (st_dev=$((dev+2)), same inode and birth time):"; drain
  rm -rf "$LAB"
}
run_case "change (HEAD $(git -C "$WT" rev-parse --short HEAD))" "$WT"
BASE=$(mktemp -d "${TMPDIR:-/tmp}/fm-base.XXXXXX"); git -C "$WT" archive 1f3e7696 bin | tar -x -C "$BASE"
run_case "base (1f3e7696, before the fix)" "$BASE"
rm -rf "$BASE"

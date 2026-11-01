#!/usr/bin/env bash
# Live Herdr lab scenarios for the durable task-copy lease.
# Usage: live-herdr-lease.sh <firstmate-root> <label> [restart-only]
set -u
ROOT=$1; LABEL=$2; MODE=${3:-full}
HELPER="$ROOT/bin/fm-herdr-lab.sh"
TMP=$(mktemp -d "$(cd "${TMPDIR:-/tmp}" && pwd -P)/fm-lease-live.XXXXXX")
export TREEHOUSE_ROOT="$TMP/pool"
SESSION=$("$HELPER" name "$LABEL") || exit 1
export HERDR_SESSION="$SESSION"
unset HERDR_ENV HERDR_PANE_ID HERDR_SOCKET_PATH HERDR_TAB_ID HERDR_WORKSPACE_ID
lab() { "$HELPER" run "$SESSION" "$@"; }
say() { printf '%s\n' "$*"; }
CLEANED=0
cleanup() {
  [ "$CLEANED" = 0 ] || return 0; CLEANED=1
  for wt in $(cd "$PROJ" 2>/dev/null && treehouse status --json 2>/dev/null | jq -r '.. | objects | .path? // empty' 2>/dev/null); do
    (cd "$PROJ" && treehouse return --force "$wt") >/dev/null 2>&1
  done
  "$HELPER" teardown "$SESSION"; say "lab teardown rc=$?"
  find "$TMP" -type d -exec chmod u+rwx {} + 2>/dev/null; rm -rf "$TMP"
}
trap cleanup EXIT
"$HELPER" provision "$SESSION" || { say "provision failed"; exit 1; }
say "== root=$ROOT session=$SESSION"

PROJ="$TMP/project"; mkdir -p "$PROJ"
git -C "$PROJ" init -q -b main; printf '# scratch\n' > "$PROJ/README.md"
git -C "$PROJ" add README.md
git -C "$PROJ" -c user.name=T -c user.email=t@example.invalid commit -qm initial
git clone -q --bare "$PROJ" "$PROJ.origin.git"; git -C "$PROJ" remote add origin "file://$PROJ.origin.git"
git -C "$PROJ" fetch -q origin

mkhome() { # <home> <presentation:on|off>
  "$ROOT/bin/fm-lab-home.sh" create "$1" >/dev/null || { say "lab home create failed"; exit 1; }
  if [ "$2" = off ]; then printf 'off\n' > "$1/config/herdr-presentation-spaces"; else : > "$1/config/herdr-presentation-spaces"; fi
}
brief() { mkdir -p "$1/data/$2"; printf '# Task\n## Captain'"'"'s intent\nLease live check %s.\n\n## Firstmate spec\nNothing.\n' "$2" > "$1/data/$2/brief.md"; }
spawn() { # <home> <id>
  env FM_SPAWN_NO_GUARD=1 FM_HOME="$1" \
    "$ROOT/bin/fm-spawn.sh" "$2" "$PROJ" "sh -c 'echo lease-live-ok'" --backend herdr --mode no-mistakes --yolo off \
    > "$TMP/$2.out" 2> "$TMP/$2.err"
  echo $?
}
leases() { (cd "$PROJ" && treehouse status --json) | jq -c '[.. | objects | select(has("path")) | {path, lease: (.lease // .leased // null), holder: (.lease_holder // .lease.holder // null)}]' 2>/dev/null || (cd "$PROJ" && treehouse status --json); }
meta() { grep "^$3=" "$1/state/$2.meta" | cut -d= -f2-; }
pane_cwd() { lab pane get "$1" 2>/dev/null | jq -r '.result.pane | "cwd=\(.cwd) foreground_cwd=\(.foreground_cwd)"'; }

H1="$TMP/home-flat"; mkhome "$H1" off; brief "$H1" leasea
say "--- S1 fresh flat spawn"
rc=$(spawn "$H1" leasea); say "spawn rc=$rc"; [ "$rc" = 0 ] || { cat "$TMP/leasea.err"; exit 1; }
WT=$(meta "$H1" leasea worktree); PANE=$(meta "$H1" leasea herdr_pane_id)
say "project=$PROJ"; say "meta worktree=$WT pane=$PANE"
say "treehouse status (raw):"; (cd "$PROJ" && treehouse status --json)
sleep 3
say "pane before restart: $(pane_cwd "$PANE")"

say "--- S2 restart the lab Herdr server"
"$HELPER" stop "$SESSION" >/dev/null || say "stop failed"
"$HELPER" provision "$SESSION" || say "re-provision failed"
sleep 3
say "pane after restart: $(pane_cwd "$PANE")"
say "panes after restart:"; lab pane list 2>/dev/null | jq -c '[.result.panes[]? | {pane_id, cwd, foreground_cwd}]'
[ "$MODE" = full ] || exit 0

say "--- S3 teardown returns the lease"
FM_HOME="$H1" "$ROOT/bin/fm-teardown.sh" leasea > "$TMP/td.out" 2>&1; say "teardown rc=$?"; tail -5 "$TMP/td.out"
say "treehouse status after teardown:"; (cd "$PROJ" && treehouse status --json)

# Make the next acquired slot unclaimable so the spawn aborts after the lease.
plant() { local m; m="$(dirname "$(cd "$WT" && pwd -P)")/.fm-slot-owner"; rm -f "$m"; mkdir -p "$m"; say "planted unclaimable claim dir $m"; }
unplant() { rmdir "$(dirname "$(cd "$WT" && pwd -P)")/.fm-slot-owner" 2>/dev/null; }

say "--- S4 flat abort after lease (endpoint left open)"
plant; brief "$H1" leaseb
rc=$(spawn "$H1" leaseb); say "spawn rc=$rc"; grep -E 'error|warning' "$TMP/leaseb.err"
say "meta exists? $([ -e "$H1/state/leaseb.meta" ] && echo yes || echo no)"
say "treehouse status after flat abort:"; (cd "$PROJ" && treehouse status --json)
(cd "$PROJ" && treehouse return --force "$WT") >/dev/null 2>&1; unplant

say "--- S5 projected abort after lease (task pane closed)"
H2="$TMP/home-proj"; mkhome "$H2" on; brief "$H2" leasec
plant
rc=$(spawn "$H2" leasec); say "spawn rc=$rc"; grep -E 'error|warning' "$TMP/leasec.err"
say "meta exists? $([ -e "$H2/state/leasec.meta" ] && echo yes || echo no)"
say "treehouse status after projected abort:"; (cd "$PROJ" && treehouse status --json)
say "lab panes:"; lab pane list 2>/dev/null | jq -c '[.result.panes[]? | {pane_id, cwd}]'
unplant

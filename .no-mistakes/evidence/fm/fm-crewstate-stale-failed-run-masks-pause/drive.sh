#!/usr/bin/env bash
# Live driver: stands up a real firstmate home with a real crew worktree and
# drives the REAL bin/fm-crew-state.sh and bin/fm-inactive-reconcile.sh.
# The only stub is the external `no-mistakes` CLI (its daemon/ledger cannot be
# conjured here); everything under test is the real product code.
set -u
ROOT=${ROOT:?}
SBX=${SBX:?}
rm -rf "$SBX"; mkdir -p "$SBX"
umask 022
export GIT_AUTHOR_NAME=fmtest GIT_AUTHOR_EMAIL=fm@test.invalid
export GIT_COMMITTER_NAME=fmtest GIT_COMMITTER_EMAIL=fm@test.invalid
export FM_GATE_REFUSE_BYPASS=1
unset FM_TASK_ID

stamp_minutes_ago() { local e=$(( $(date +%s) - $1 * 60 )); date -r "$e" '+%Y-%m-%d %H:%M'; }
backdate() { local e=$(( $(date +%s) - $2 * 60 )); touch -t "$(date -r "$e" +%Y%m%d%H%M.%S)" "$1"; }
age() { local e=$(( $(date +%s) - 120 )); touch -t "$(date -r "$e" +%Y%m%d%H%M.%S)" "$@"; }

make_fakebin() { # <world>
  local fb="$1/fakebin"; mkdir -p "$fb"
  cat > "$fb/no-mistakes" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  axi) shift
    [ "$#" = 0 ] && { printf '%s\n' "${FM_FAKE_AXI_STATUS:-}"; exit 0; }
    case "${1:-}" in
      status) shift
        if [ "${1:-}" = --run ]; then printf '%s\n' "${FM_FAKE_AXI_STATUS:-}"; else printf '%s\n' "${FM_FAKE_AXI_STATUS:-}"; fi ;;
      logs) printf '\n' ;;
    esac ;;
  runs) printf '%s\n' "${FM_FAKE_RUNS_LIST:-}" ;;
  daemon) printf 'daemon running (pid 4242)\n'; exit 0 ;;
esac
exit 0
SH
  cat > "$fb/tmux" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  display-message) printf '%%1\n' ;;
  capture-pane) printf 'all quiet\n> \n' ;;
esac
SH
  local t
  for t in gh gh-axi curl glab; do
    cat > "$fb/$t" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$(basename "$0")" >> "${FM_FORGE_LOG:-/dev/null}"
exit 97
SH
  done
  chmod +x "$fb"/*
}

new_world() { # <name>
  WORLD="$SBX/$1"; MAIN="$WORLD/main"
  mkdir -p "$WORLD/root" "$MAIN"/{state,data,config,projects}
  make_fakebin "$WORLD"
  : > "$WORLD/forge.log"
}

make_crew() { # <id> <branch> <status-line> [status-age-min]
  local id=$1 branch=$2 line=$3 agemin=${4:-}
  local wt="$MAIN/projects/$id"
  mkdir -p "$wt"
  git -C "$wt" init -q
  git -C "$wt" commit -q --allow-empty -m init
  git -C "$wt" checkout -q -b "$branch"
  HEAD_FULL=$(git -C "$wt" rev-parse HEAD)
  HEAD_SHORT=$(git -C "$wt" rev-parse --short=8 HEAD)
  export FM_FAKE_RUN_HEAD=$HEAD_FULL
  cat > "$MAIN/state/$id.meta" <<META
window=firstmate:fm-$id
worktree=$wt
project=alpha
harness=codex
kind=ship
mode=no-mistakes
yolo=off
spawn_gen=s$$.$RANDOM
pr=https://example.test/owner/repo/pull/1
META
  printf '%s\n' "$line" > "$MAIN/state/$id.status"
  : > "$MAIN/state/$id.turn-ended"
  age "$MAIN/state/$id.meta" "$MAIN/state/$id.turn-ended"
  if [ -n "$agemin" ]; then backdate "$MAIN/state/$id.status" "$agemin"; else age "$MAIN/state/$id.status"; fi
}

read_state() { # <id>
  PATH="$WORLD/fakebin:$PATH" FM_STATE_OVERRIDE="$MAIN/state" FM_CREW_STATE_NO_FORGE=1 \
    "$ROOT/bin/fm-crew-state.sh" "$1"
}

reconcile() {
  PATH="$WORLD/fakebin:$PATH" FM_ROOT_OVERRIDE="$WORLD/root" FM_HOME="$MAIN" \
    FM_STATE_OVERRIDE="$MAIN/state" FM_DATA_OVERRIDE="$MAIN/data" FM_CONFIG_OVERRIDE="$MAIN/config" \
    FM_INACTIVE_RECONCILE_SECS=60 FM_INACTIVE_CREW_STATE_BIN="$ROOT/bin/fm-crew-state.sh" \
    FM_FORGE_LOG="$WORLD/forge.log" "$ROOT/bin/fm-inactive-reconcile.sh" scan --startup
}

captain_wakes() { grep -c 'inactive-outcome:' "$MAIN/state/.wake-queue" 2>/dev/null || printf 0; }
outcome_records() { find "$MAIN/state/terminal-outcomes" -type f -name '*.pending' 2>/dev/null | wc -l | tr -d ' '; }
dump_record() {
  local f
  for f in "$MAIN/state/terminal-outcomes"/*.pending; do [ -f "$f" ] && { echo "--- durable terminal outcome record ---"; cat "$f"; }; done
}

hr() { printf '\n================ %s ================\n' "$*"; }

##############################################################################
hr "S1  stale failed run must not mask the crew's later pause (the titular bug)"
new_world s1
make_crew c1 fm/feat-s1 'paused: waiting on a human answer for the API shape'
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-s1
  status: completed
  head: \"$HEAD_FULL\"
  pr: \"\"
  findings: none
outcome: failed"
export FM_FAKE_RUNS_LIST="  failed     fm/feat-s1 f0f0f0f0  $(stamp_minutes_ago 60)"
echo "\$ no-mistakes runs  (branch ledger)"; printf '%s\n' "$FM_FAKE_RUNS_LIST"
echo "\$ cat state/c1.status"; cat "$MAIN/state/c1.status"
echo "\$ fm-crew-state.sh c1"; read_state c1
echo "\$ fm-inactive-reconcile.sh scan --startup"; reconcile
echo "captain wakes queued: $(captain_wakes)   durable terminal outcome records: $(outcome_records)"

##############################################################################
hr "S2  routine ship shape: done: before the run, run fails, crew silent"
new_world s2
make_crew c2 fm/feat-s2 'done: implementation complete' 120
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-s2
  status: completed
  head: \"$HEAD_FULL\"
  pr: \"https://example.test/owner/repo/pull/77\"
  findings: none
outcome: failed"
export FM_FAKE_RUNS_LIST="  failed     fm/feat-s2 ${HEAD_SHORT}  $(stamp_minutes_ago 60) https://example.test/owner/repo/pull/77"
echo "\$ no-mistakes runs  (branch ledger)"; printf '%s\n' "$FM_FAKE_RUNS_LIST"
echo "\$ cat state/c2.status"; cat "$MAIN/state/c2.status"
echo "\$ fm-crew-state.sh c2"; read_state c2
echo "\$ fm-inactive-reconcile.sh scan --startup"; reconcile
echo "captain wakes queued: $(captain_wakes)   durable terminal outcome records: $(outcome_records)"
dump_record
echo "\$ grep inactive-outcome state/.wake-queue"; grep 'inactive-outcome' "$MAIN/state/.wake-queue" | head -3

##############################################################################
hr "S3  ADVERSARIAL: a done: written MID-RUN must not mask the current failure"
new_world s3
make_crew c3 fm/feat-s3 'done: implementation complete' 40
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-s3
  status: completed
  head: \"$HEAD_FULL\"
  pr: \"\"
  findings: none
outcome: failed"
export FM_FAKE_RUNS_LIST="  failed     fm/feat-s3 ${HEAD_SHORT}  $(stamp_minutes_ago 60)"
echo "\$ no-mistakes runs  (branch ledger; row IS the attributed run)"; printf '%s\n' "$FM_FAKE_RUNS_LIST"
echo "\$ cat state/c3.status  (written 40 min ago, run started 60 min ago -> mid-run)"; cat "$MAIN/state/c3.status"
echo "\$ fm-crew-state.sh c3"; read_state c3

##############################################################################
hr "S4  ADVERSARIAL: a LIVE replacement run outranks the crew's own done:"
new_world s4
make_crew c4 fm/feat-s4 'done: implementation complete' 30
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-s4
  status: completed
  head: \"$HEAD_FULL\"
  pr: \"\"
  findings: none
outcome: failed"
export FM_FAKE_RUNS_LIST="  running    fm/feat-s4 f0f0f0f0  $(stamp_minutes_ago 60)"
echo "\$ no-mistakes runs  (newest row is LIVE)"; printf '%s\n' "$FM_FAKE_RUNS_LIST"
echo "\$ cat state/c4.status"; cat "$MAIN/state/c4.status"
echo "\$ fm-crew-state.sh c4"; read_state c4
echo "\$ fm-inactive-reconcile.sh scan --startup"; reconcile
echo "captain wakes queued: $(captain_wakes)   durable terminal outcome records: $(outcome_records)"

##############################################################################
hr "S5  a terminal outcome never names a PR its run did not open"
new_world s5
make_crew c5 fm/feat-s5 'working: implementing the parser'
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-s5
  status: completed
  head: \"$HEAD_FULL\"
  pr: \"\"
  findings: none
outcome: failed"
export FM_FAKE_RUNS_LIST="  failed     fm/feat-s5 ${HEAD_SHORT}  $(stamp_minutes_ago 60)"
echo "meta records an older task PR:"; grep '^pr=' "$MAIN/state/c5.meta"
echo "\$ no-mistakes runs  (run opened NO pr)"; printf '%s\n' "$FM_FAKE_RUNS_LIST"
echo "\$ fm-crew-state.sh c5"; read_state c5
echo "\$ fm-inactive-reconcile.sh scan --startup"; reconcile
echo "captain wakes queued: $(captain_wakes)   durable terminal outcome records: $(outcome_records)"
dump_record

echo
echo "forge calls made during reconciliation (must be empty):"
cat "$WORLD/forge.log"

##############################################################################
hr "S6  ADVERSARIAL: crew prose cannot forge the reader's ordering field"
new_world s6
TOKEN=$(bash -c '. "$1"; printf %s "$FM_CREW_STATE_WORD_OLDER_DETAIL"' _ "$ROOT/bin/fm-classify-lib.sh")
make_crew c6 fm/feat-s6 "done: implementation complete · $TOKEN"
printf 'failed: the build broke\n' >> "$MAIN/state/c6.status"
age "$MAIN/state/c6.status"
# The reader answers a status-log done whose crew-authored note ends in the token.
cat > "$WORLD/fakebin/reader.sh" <<SH
#!/usr/bin/env bash
printf 'state: done · source: status-log · implementation complete · $TOKEN\n'
SH
chmod +x "$WORLD/fakebin/reader.sh"
echo "\$ cat state/c6.status"; cat "$MAIN/state/c6.status"
echo "state line handed to the reconciler:"; "$WORLD/fakebin/reader.sh"
PATH="$WORLD/fakebin:$PATH" FM_ROOT_OVERRIDE="$WORLD/root" FM_HOME="$MAIN" \
  FM_STATE_OVERRIDE="$MAIN/state" FM_DATA_OVERRIDE="$MAIN/data" FM_CONFIG_OVERRIDE="$MAIN/config" \
  FM_INACTIVE_RECONCILE_SECS=60 FM_INACTIVE_CREW_STATE_BIN="$WORLD/fakebin/reader.sh" \
  FM_FORGE_LOG="$WORLD/forge.log" "$ROOT/bin/fm-inactive-reconcile.sh" scan --startup
echo "captain wakes queued: $(captain_wakes)   durable terminal outcome records: $(outcome_records)"

##############################################################################
hr "S7  mid-run done: the crew's un-ordered word still suppresses presentation"
new_world s7
make_crew c7 fm/feat-s7 'done: implementation complete' 40
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-s7
  status: completed
  head: \"$HEAD_FULL\"
  pr: \"\"
  findings: none
outcome: failed"
export FM_FAKE_RUNS_LIST="  failed     fm/feat-s7 ${HEAD_SHORT}  $(stamp_minutes_ago 60)"
echo "\$ fm-crew-state.sh c7"; read_state c7
echo "\$ fm-inactive-reconcile.sh scan --startup"; reconcile
echo "captain wakes queued: $(captain_wakes)   durable terminal outcome records: $(outcome_records)"

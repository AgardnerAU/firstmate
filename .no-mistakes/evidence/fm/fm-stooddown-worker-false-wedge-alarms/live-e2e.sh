#!/usr/bin/env bash
# Live end-to-end driver for the stood-down-worker change.
#
# Nothing here is stubbed on the product side: a REAL tmux server (private
# socket), a REAL git project and worktree, a REAL firstmate home, and a REAL
# compiled process in the pane whose name the liveness classifier reads. Only
# the third-party `no-mistakes` CLI is a stub, because the product shells out
# to it and this run must not touch the host's gate.
set -u

ROOT=${ROOT:?}
EV=${EV:?}
SB=$(mktemp -d "${TMPDIR:-/tmp}/fm-live.XXXXXX")
SOCKET="fm-live-$$"
REAL_TMUX=$(command -v tmux)
PASS=0
FAIL=0

log() { printf '%s\n' "$*"; }
pass() { PASS=$((PASS + 1)); printf 'PASS - %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }

cleanup() {
  "$REAL_TMUX" -L "$SOCKET" kill-server >/dev/null 2>&1 || true
  rm -rf "$SB"
}
trap cleanup EXIT

mkdir -p "$SB/bin" "$SB/shim"

# --- a tmux shim pinning every product tmux call to a private socket ---------
cat > "$SB/shim/tmux" <<SH
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCKET" "\$@"
SH
chmod +x "$SB/shim/tmux"

# --- the harness stand-in ----------------------------------------------------
cat > "$SB/claude.c" <<'C'
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
  char line[4096];
  (void)argc; (void)argv;
  for (;;) {
    printf("\033[2J\033[H");
    printf("fake harness pane\n\n");
    printf("\xe2\x9d\xaf\xc2\xa0");
    fflush(stdout);
    if (!fgets(line, sizeof line, stdin)) return 0;
    size_t n = strlen(line);
    while (n && (line[n-1] == '\n' || line[n-1] == '\r')) line[--n] = 0;
    if (!strcmp(line, "/exit")) return 0;
  }
}
C
cc -o "$SB/bin/claude" "$SB/claude.c" || { echo "cc failed"; exit 1; }

# --- the no-mistakes stub (env-driven, so the host's gate is never touched) --
cat > "$SB/bin/no-mistakes" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-} ${2:-}" in
  "axi status") printf '%s\n' "${FM_FAKE_AXI_STATUS:-}" ;;
  "runs "*|"runs") printf '%s\n' "${FM_FAKE_RUNS_LIST:-}" ;;
esac
exit 0
SH
chmod +x "$SB/bin/no-mistakes"

export PATH="$SB/shim:$SB/bin:$PATH"
# The documented test-harness escape hatch: this driver runs from a no-mistakes
# gate worktree, exactly the case tests/lib.sh exports it for.
export FM_GATE_REFUSE_BYPASS=1
export GIT_AUTHOR_NAME=fmtest GIT_AUTHOR_EMAIL=fmtest@example.invalid
export GIT_COMMITTER_NAME=fmtest GIT_COMMITTER_EMAIL=fmtest@example.invalid

tmux new-session -d -s bootstrap -c "$SB" || { echo "tmux session failed"; exit 1; }

# --- case construction -------------------------------------------------------
CASE=0
new_case() {  # <name> -> prints case dir
  CASE=$((CASE + 1))
  local name=$1 dir proj wt
  dir="$SB/case$CASE-$name"
  mkdir -p "$dir/home/state" "$dir/home/data/t1"
  proj="$dir/proj"; wt="$dir/wt"
  mkdir -p "$proj"
  git -C "$proj" init -q -b main
  : > "$proj/README"
  git -C "$proj" add README
  git -C "$proj" commit -qm init
  git -C "$proj" worktree add -q -b "task-$name" "$wt" >/dev/null
  cat > "$dir/home/data/t1/brief.md" <<'BRIEF'
# Task
## Captain's intent
Hold this task and bring the worker back later.

## Firstmate spec
Exercise the stood-down worker lifecycle end to end.
BRIEF
  {
    echo "window=s-$name:fm-t1"
    echo "endpoint_task_id=t1"
    echo "worktree=$wt"
    echo "project=$proj"
    echo "harness=claude"
    echo "kind=ship"
    echo "mode=no-mistakes"
    echo "yolo=off"
    echo "model=default"
    echo "effort=default"
  } > "$dir/home/state/t1.meta"
  printf '%s\n' "$dir"
}

win_of() { sed -n 's/^window=//p' "$1/home/state/t1.meta"; }

start_agent() {  # <case-dir>
  local dir=$1 win ses wname wt
  win=$(win_of "$dir"); ses=${win%%:*}; wname=${win#*:}
  wt=$(sed -n 's/^worktree=//p' "$dir/home/state/t1.meta")
  # The pane shell is a profile-free bash with a PATH that resolves `claude` to
  # the harness stand-in, so a relaunch can never reach a real harness on the
  # host's PATH.
  local pane_shell="env PATH=$SB/bin:/usr/bin:/bin bash --noprofile --norc"
  tmux has-session -t "=$ses" 2>/dev/null || tmux new-session -d -s "$ses" -c "$wt" "$pane_shell"
  tmux list-windows -t "=$ses" -F '#{window_name}' | grep -qx "$wname" \
    || tmux new-window -d -t "$ses:" -n "$wname" -c "$wt" "$pane_shell"
  tmux set-window-option -t "$win" automatic-rename off >/dev/null 2>&1 || true
  tmux set-window-option -t "$win" allow-rename off >/dev/null 2>&1 || true
  tmux send-keys -t "$win" "claude" Enter
  local i=0
  while [ "$i" -lt 100 ]; do
    [ "$(tmux display-message -p -t "$win" '#{pane_current_command}')" = claude ] && return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}

pane_command() { tmux display-message -p -t "$1" '#{pane_current_command}'; }

control() {  # <case-dir> <args...>
  local dir=$1; shift
  env -u NO_MISTAKES_GATE FM_HOME="$dir/home" FM_CONTROL_POLL=0.2 FM_CONTROL_SETTLE_WAIT=1 \
    FM_CONTROL_EXIT_WAIT=15 FM_CONTROL_LAUNCH_WAIT=30 \
    "$ROOT/bin/fm-control.sh" "$@" 2>&1
}

crew_state() {  # <case-dir> <id>
  local dir=$1; shift
  env -u NO_MISTAKES_GATE FM_HOME="$dir/home" FM_CREW_STATE_NO_FORGE=1 "$ROOT/bin/fm-crew-state.sh" "$@" 2>&1
}

send() {  # <case-dir> <args...>
  local dir=$1; shift
  env -u NO_MISTAKES_GATE FM_HOME="$dir/home" "$ROOT/bin/fm-send.sh" "$@" 2>&1
}

banner() { printf '\n===== %s =====\n' "$1"; }

########################################################################
banner "S1/S2/S3 stand-down of a live worker, then crew-state and fm-send"
D=$(new_case hold)
start_agent "$D" || { fail "S1 setup: the harness process never came up in the pane"; }
log "pane command before stand-down: $(pane_command "$(win_of "$D")")"
log "crew-state before stand-down: $(crew_state "$D" t1)"
OUT=$(control "$D" t1 stand-down)
log "\$ fm-control.sh t1 stand-down"
log "$OUT"
case "$OUT" in
  "stood-down t1 harness=claude backend=tmux endpoint=$(win_of "$D") worktree=$(sed -n 's/^worktree=//p' "$D/home/state/t1.meta")")
    pass "S1 stand-down reported stood-down for the live worker" ;;
  *) fail "S1 stand-down did not report a clean hold: $OUT" ;;
esac
log "pane command after stand-down: $(pane_command "$(win_of "$D")")"
log "worker-state record:"; sed 's/^/  /' "$D/home/state/t1.worker-state" 2>/dev/null
if [ "$(pane_command "$(win_of "$D")")" != claude ] \
   && grep -qx 'state=stood-down' "$D/home/state/t1.worker-state" 2>/dev/null; then
  pass "S1 the agent is gone and the endpoint survives with a durable stood-down record"
else
  fail "S1 the agent or the record is not in the declared state"
fi

CS=$(crew_state "$D" t1)
log "\$ fm-crew-state.sh t1"
log "$CS"
case "$CS" in
  *"state: parked"*"source: worker-state"*"worker deliberately stood down"*)
    pass "S2 crew-state reports the hold as parked with a worker-state source" ;;
  *) fail "S2 crew-state did not report the hold: $CS" ;;
esac

SOUT=$(send "$D" t1 "please pick this back up"); SRC=$?
log "\$ fm-send.sh t1 'please pick this back up' (exit $SRC)"
log "$SOUT"
if [ "$SRC" -ne 0 ] && [ ! -d "$D/home/state/t1.inbox" ]; then
  pass "S3 fm-send refuses to enqueue an instruction a proven worker-free task cannot read"
else
  fail "S3 fm-send did not refuse the steer (exit $SRC): $SOUT"
fi

########################################################################
banner "S4 relaunch reuses the endpoint and worktree and clears the hold"
ROUT=$(control "$D" t1 relaunch --note "back on deck")
log "\$ fm-control.sh t1 relaunch --note 'back on deck'"
log "$ROUT"
NEWWIN=$(sed -n 's/^window=//p' "$D/home/state/t1.meta")
NEWWT=$(sed -n 's/^worktree=//p' "$D/home/state/t1.meta")
log "endpoint after relaunch: $NEWWIN  worktree: $NEWWT  pane: $(pane_command "$NEWWIN")"
if [ "$NEWWIN" = "$(win_of "$D")" ] && [ ! -e "$D/home/state/t1.worker-state" ] \
   && [ "$(pane_command "$NEWWIN")" = claude ]; then
  pass "S4 relaunch brought a worker back in the same endpoint and cleared the hold"
else
  fail "S4 relaunch did not restore a worker in place: $ROUT"
fi
CS=$(crew_state "$D" t1)
log "crew-state after relaunch: $CS"
case "$CS" in
  *"parked"*"worker-state"*) fail "S4 crew-state still reports a hold after relaunch: $CS" ;;
  *) pass "S4 crew-state no longer reports a hold after relaunch" ;;
esac
SOUT=$(send "$D" t1 "steer after relaunch"); SRC=$?
log "\$ fm-send.sh t1 'steer after relaunch' (exit $SRC)"
log "$SOUT"
[ "$SRC" -eq 0 ] && pass "S4 fm-send works again once a worker is back" \
  || fail "S4 fm-send still refuses after relaunch: $SOUT"

########################################################################
banner "S5 adversarial: repair-worker-state clears a record a live worker contradicts"
D2=$(new_case repair)
start_agent "$D2" || fail "S5 setup: harness did not start"
control "$D2" t1 stand-down >/dev/null
start_agent "$D2" || fail "S5 setup: harness did not restart behind the record"
log "pane command behind the stood-down record: $(pane_command "$(win_of "$D2")")"
CS=$(crew_state "$D2" t1)
log "crew-state with a live worker behind the record: $CS"
case "$CS" in
  *"unknown"*"worker-state"*"live worker"*) pass "S5 crew-state refuses to call a live worker a healthy hold" ;;
  *) fail "S5 crew-state masked a live worker: $CS" ;;
esac
ROUT=$(control "$D2" t1 repair-worker-state)
log "\$ fm-control.sh t1 repair-worker-state"
log "$ROUT"
if [ ! -e "$D2/home/state/t1.worker-state" ] && [ "${ROUT#*cleared-live-worker}" != "$ROUT" ]; then
  pass "S5 repair-worker-state cleared the contradicted record and warned"
else
  fail "S5 repair-worker-state did not clear the contradicted record: $ROUT"
fi

########################################################################
banner "S6 adversarial: stand-down is refused while the branch owns an active run"
D3=$(new_case activerun)
start_agent "$D3" || fail "S6 setup: harness did not start"
HEAD_SHA=$(git -C "$D3/wt" rev-parse HEAD)
OUT=$(FM_FAKE_AXI_STATUS="id: run-42
status: running
branch: \"task-activerun\"
head: \"$HEAD_SHA\"" control "$D3" t1 stand-down)
log "\$ fm-control.sh t1 stand-down (with an active run on the branch)"
log "$OUT"
if [ ! -e "$D3/home/state/t1.worker-state" ] && [ "${OUT#*active no-mistakes run}" != "$OUT" ] \
   && [ "$(pane_command "$(win_of "$D3")")" = claude ]; then
  pass "S6 an in-flight run refuses the hold, names the run, and leaves the worker running"
else
  fail "S6 the active run did not refuse the hold: $OUT"
fi

########################################################################
banner "S7 adversarial: only the branch's NEWEST ledger row decides"
# Newest row for this branch is terminal, an older row is still 'running'.
OUT=$(FM_FAKE_AXI_STATUS="" \
  FM_FAKE_RUNS_LIST="completed task-activerun $HEAD_SHA
running task-activerun $HEAD_SHA" control "$D3" t1 stand-down)
log "\$ fm-control.sh t1 stand-down (newest row completed, older row running)"
log "$OUT"
if grep -qx 'state=stood-down' "$D3/home/state/t1.worker-state" 2>/dev/null; then
  pass "S7 a stale older live row no longer blocks a hold behind a newer terminal row"
else
  fail "S7 the hold was refused despite a newer terminal row: $OUT"
fi
# And the converse: newest row still live must refuse.
D4=$(new_case newestlive)
start_agent "$D4" || fail "S7 setup: harness did not start"
HEAD4=$(git -C "$D4/wt" rev-parse HEAD)
OUT=$(FM_FAKE_AXI_STATUS="" \
  FM_FAKE_RUNS_LIST="running task-newestlive $HEAD4
completed task-newestlive $HEAD4" control "$D4" t1 stand-down)
log "\$ fm-control.sh t1 stand-down (newest row running)"
log "$OUT"
if [ ! -e "$D4/home/state/t1.worker-state" ] && [ "${OUT#*active no-mistakes run}" != "$OUT" ]; then
  pass "S7 a newest live ledger row still refuses the hold"
else
  fail "S7 a newest live ledger row failed to refuse the hold: $OUT"
fi

########################################################################
banner "S8 adversarial: an unacknowledged steering instruction refuses the hold"
D5=$(new_case pending)
start_agent "$D5" || fail "S8 setup: harness did not start"
SOUT=$(send "$D5" t1 "read this before you stand down"); SRC=$?
log "\$ fm-send.sh t1 'read this before you stand down' (exit $SRC)"
OUT=$(control "$D5" t1 stand-down)
log "\$ fm-control.sh t1 stand-down (with an unread instruction waiting)"
log "$OUT"
if [ ! -e "$D5/home/state/t1.worker-state" ] && [ "${OUT#*unacknowledged instruction}" != "$OUT" ]; then
  pass "S8 an unread steering instruction refuses the hold and names it"
else
  fail "S8 the unread instruction did not refuse the hold: $OUT"
fi


########################################################################
banner "S9 the watcher itself: a declared hold raises no wedge alarm, an undeclared one does"
watch_bg() {  # <case-dir> <out>
  local dir=$1 out=$2
  env -u NO_MISTAKES_GATE FM_STATE_OVERRIDE="$dir/home/state" FM_HOME="$dir/home" \
    FM_POLL=1 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 \
    FM_STALE_SECS=1 FM_STALE_ESCALATE_SECS=1 \
    "$ROOT/bin/fm-watch.sh" > "$out" 2>&1 &
  printf '%s' "$!"
}

D6=$(new_case watchhold)
start_agent "$D6" || fail "S9 setup: harness did not start"
control "$D6" t1 stand-down >/dev/null
WOUT="$D6/watch.out"
WPID=$(watch_bg "$D6" "$WOUT")
sleep 8
if kill -0 "$WPID" 2>/dev/null; then
  ALIVE=yes
else
  ALIVE=no
fi
log "watcher still supervising after 8s: $ALIVE"
log "watcher output: $(cat "$WOUT")"
log "pane hashes recorded: $(ls "$D6/home/state" | grep -c '^\.hash-' || true)"
kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null
if [ "$ALIVE" = yes ] && [ ! -s "$WOUT" ] && [ ! -s "$D6/home/state/.wake-queue" ] \
   && [ -z "$(ls -A "$D6/home/state" | grep '^\.hash-' || true)" ]; then
  pass "S9 a declared hold raises no wedge alarm and is not even pane-hashed"
else
  fail "S9 the declared hold still woke the watcher: $(cat "$WOUT")"
fi

D7=$(new_case watchdead)
start_agent "$D7" || fail "S9 setup: harness did not start"
control "$D7" t1 exit >/dev/null
WOUT2="$D7/watch.out"
WPID2=$(watch_bg "$D7" "$WOUT2")
i=0
while [ "$i" -lt 60 ]; do
  kill -0 "$WPID2" 2>/dev/null || break
  sleep 0.5; i=$((i + 1))
done
kill "$WPID2" 2>/dev/null; wait "$WPID2" 2>/dev/null
log "watcher output for the same endpoint stopped WITHOUT a declared hold:"
log "$(cat "$WOUT2")"
if grep -q "$(win_of "$D7")" "$WOUT2" 2>/dev/null; then
  pass "S9 an undeclared stopped worker still raises the alarm on the same endpoint"
else
  fail "S9 the undeclared stopped worker raised no alarm, so the suppression proves nothing: $(cat "$WOUT2")"
fi


########################################################################
banner "S10 adversarial: a vanished endpoint is never reported as a healthy hold"
D8=$(new_case vanished)
start_agent "$D8" || fail "S10 setup: harness did not start"
control "$D8" t1 stand-down >/dev/null
CS=$(crew_state "$D8" t1)
log "crew-state while the endpoint is intact: $CS"
tmux kill-window -t "$(win_of "$D8")"
CS=$(crew_state "$D8" t1)
log "crew-state after the endpoint vanished: $CS"
case "$CS" in
  *"unknown"*"worker-state"*"endpoint is gone: $(win_of "$D8")"*)
    pass "S10 a vanished endpoint reports unknown and names the lost endpoint" ;;
  *) fail "S10 the vanished endpoint was not reported: $CS" ;;
esac
SOUT=$(send "$D8" t1 "steer to a vanished endpoint"); SRC=$?
log "\$ fm-send.sh t1 'steer to a vanished endpoint' (exit $SRC)"
log "$SOUT"
if [ -e "$D8/home/state/t1.inbox/001.msg" ]; then
  pass "S10 a merely missing endpoint stays on the ordinary durable-inbox path"
else
  fail "S10 the steer to a missing endpoint was not durably recorded: $SOUT"
fi

########################################################################
banner "S11 adversarial: a malformed worker-state record suppresses nothing"
D9=$(new_case malformed)
start_agent "$D9" || fail "S11 setup: harness did not start"
control "$D9" t1 stand-down >/dev/null
# Corrupt the persisted record the way a hand-edit or a truncated write would.
printf 'schema=1\ntask_id=t1\nendpoint=somewhere:else\nstate=stood-down\n' \
  > "$D9/home/state/t1.worker-state"
CS=$(crew_state "$D9" t1)
log "crew-state with a record bound to another endpoint: $CS"
case "$CS" in
  *"unknown"*"worker-state"*"invalid worker-state record"*)
    pass "S11 an invalid record reports unknown and points at repair" ;;
  *) fail "S11 the invalid record was not reported: $CS" ;;
esac
OUT=$(control "$D9" t1 stand-down)
log "\$ fm-control.sh t1 stand-down (with an invalid record)"
log "$OUT"
case "$OUT" in
  *"invalid worker-state record"*repair-worker-state*) pass "S11 stand-down refuses over an invalid record and names the repair verb" ;;
  *) fail "S11 stand-down did not refuse over the invalid record: $OUT" ;;
esac
OUT=$(control "$D9" t1 repair-worker-state)
log "\$ fm-control.sh t1 repair-worker-state"
log "$OUT"
if [ ! -e "$D9/home/state/t1.worker-state" ]; then
  pass "S11 repair clears the invalid record back to ordinary supervision"
else
  fail "S11 repair left the invalid record in place: $OUT"
fi

printf '\n===== live driver summary: %s passed, %s failed =====\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

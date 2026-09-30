#!/usr/bin/env bash
# Live validation for PR #3050: a self-hosted away daemon (running as a
# background job INSIDE the supervisor pane it injects into) must not read the
# pane's pinned native `working` as the agent being mid-turn.
#
# Real herdr, isolated fm-lab-* session via bin/fm-herdr-lab.sh. The fixture
# "agent" pins its native agent_status to `working` for its whole life (the
# measured vendor behaviour while a background job runs) while rendering an
# idle `❯ ` composer. Usage: self-hosted-live.sh <worktree-root>
set -u
ROOT=$1
DAEMON="$ROOT/bin/fm-supervise-daemon.sh"
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane
SESSION="fm-lab-selfhost-$$"
export HERDR_SESSION="$SESSION"
W=$(mktemp -d "${TMPDIR:-/tmp}/fm-selfhost-live.XXXXXX")
RC=0
say() { printf '%s\n' "$*"; }
result() { say "RESULT $1 - $2"; [ "$1" = PASS ] || RC=1; }
cleanup() {
  for p in "$W"/*/state/.supervise-daemon.pid; do
    [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null
  done
  pkill -f "$W/" 2>/dev/null
  fm_herdr_lab_teardown "$SESSION" >/dev/null 2>&1 && say "teardown: $SESSION removed"
  if [ -n "${KEEP:-}" ]; then say "kept $W"; else rm -rf "$W"; fi
}
trap cleanup EXIT
fm_herdr_lab_prepare "$SESSION" || { say "prepare failed"; exit 1; }
. "$DAEMON"
fm_backend_source herdr || exit 1
say "herdr: $(herdr --version)  session: $SESSION"

CONTAINER_RAW=$(fm_backend_herdr_container_ensure /tmp) || exit 1
CONTAINER=${CONTAINER_RAW%%$'\t'*}
SEEDED=${CONTAINER_RAW#*$'\t'}

# Swallow-every-Enter shim (active only while <case>/swallow exists).
# Resolve the real binary: a PATH wrapper that execs "the next herdr on PATH"
# would otherwise find this shim again and loop forever.
REAL_HERDR=
for c in $(type -ap herdr); do
  head -c 4 "$c" | grep -q '^#!' || { REAL_HERDR=$c; break; }
done
[ -n "$REAL_HERDR" ] || { say "no real herdr binary"; exit 1; }
say "shim forwards to: $REAL_HERDR"
mkdir -p "$W/shim"
cat > "$W/shim/herdr" <<SHIM
#!/usr/bin/env bash
if [ "\${1:-}" = pane ] && [ "\${2:-}" = send-keys ] && [ -n "\${FM_LIVE_SWALLOW:-}" ] && [ -f "\$FM_LIVE_SWALLOW" ]; then
  for a in "\$@"; do [ "\$a" = enter ] && exit 0; done
fi
exec "$REAL_HERDR" "\$@"
SHIM
chmod +x "$W/shim/herdr"

cat > "$W/agent.sh" <<'AGENT'
#!/usr/bin/env bash
# args: <log> <render-busy 0|1> <daemon-launcher or ->
LOG=$1 BUSY=$2 LAUNCH=$3
herdr pane report-agent "$HERDR_PANE_ID" --source fm-live --agent fm-live --state working --session "$HERDR_SESSION" >/dev/null 2>&1
printf 'pane-env HERDR_ENV=%s HERDR_SESSION=%s HERDR_PANE_ID=%s\n' "${HERDR_ENV:-}" "${HERDR_SESSION:-}" "${HERDR_PANE_ID:-}" > "$LOG.env"
[ "$LAUNCH" = - ] || { bash "$LAUNCH" & }
stty -echo -icanon min 1 time 0 2>/dev/null
_buf=
redraw() { local s=$_buf; [ ${#s} -gt 40 ] && s="...${s: -37}"; printf '\r\033[K❯ %s' "$s"; }
[ "$BUSY" = 1 ] && printf '• Working (5s • esc to interrupt)\n'
redraw
while IFS= read -r -n 1 c; do
  if [ -z "$c" ] || [ "$c" = $'\r' ]; then
    printf '%s\t%s\n' "$(printf '%s' "$_buf" | od -An -tx1 | tr -d ' \n')" "$_buf" >> "$LOG"
    _buf=; printf '\r\033[K\n'; [ "$BUSY" = 1 ] && printf '• Working (5s • esc to interrupt)\n'; redraw
  else
    case "$c" in $'\177') _buf=${_buf%?} ;; *) _buf+=$c ;; esac; redraw
  fi
done
AGENT

new_pane() {  # <name> -> PANE
  local ids tab pane i n=0
  ids=$(fm_backend_herdr_create_task "$CONTAINER" "$1" /tmp "$SEEDED") || return 1
  SEEDED=
  read -r tab pane <<<"$ids"
  for i in $(seq 1 100); do
    fm_backend_herdr_cli "$SESSION" pane process-info --pane "$pane" 2>/dev/null | jq -e '.result.process_info as $p | ($p.foreground_processes|length==1) and ($p.foreground_processes[0].pid==$p.shell_pid)' >/dev/null 2>&1 && n=$((n+1)) || n=0
    [ $n -ge 10 ] && break; sleep 0.1
  done
  PANE=$pane
}

# daemon_env <case-dir> <target> <swallow 0|1> -> writes launcher script
daemon_launcher() {
  local d=$1 target=$2 sw=$3 extra=${4:-}
  cat > "$d/launch.sh" <<L
export PATH="$W/shim:\$PATH" FM_LIVE_SWALLOW="$d/$( [ "$sw" = 1 ] && echo swallow || echo noswallow )"
export FM_DAEMON_PRIMARY_HARNESS=codex FM_STATE_OVERRIDE="$d/state" FM_SUPERVISOR_BACKEND=herdr FM_SUPERVISOR_TARGET="$target"
export FM_ESCALATE_BATCH_SECS=0 FM_HOUSEKEEPING_TICK=1 FM_POLL=1 FM_SIGNAL_GRACE=1 FM_HEARTBEAT=999999 FM_CHECK_INTERVAL=999999
export FM_INJECT_CONFIRM_SLEEP=0.4 FM_INJECT_CONFIRM_RETRIES=4 FM_STALE_ESCALATE_SECS=999999 $extra
exec nohup "$DAEMON" >"$d/daemon.out" 2>"$d/daemon.err"
L
}

run_case() {  # <name> <render-busy> <hosting: self|terminal> <swallow> <extra-env>
  local name=$1 busy=$2 hosting=$3 sw=$4 extra=${5:-} d="$W/$1" target
  mkdir -p "$d/state"; : > "$d/submitted.log"
  [ "$sw" = 1 ] && touch "$d/swallow"
  new_pane "fm-live-$name" || { say "pane create failed"; return 1; }
  target="$SESSION:$PANE"
  afk_enter "$d/state"
  daemon_launcher "$d" "$target" "$sw" "$extra"
  if [ "$hosting" = self ]; then
    fm_backend_herdr_send_text_line "$target" "(exec -a codex bash '$W/agent.sh' '$d/submitted.log' $busy '$d/launch.sh')"
  else
    fm_backend_herdr_send_text_line "$target" "(exec -a codex bash '$W/agent.sh' '$d/submitted.log' $busy -)"
    sleep 1; ( env -u HERDR_ENV -u HERDR_PANE_ID bash "$d/launch.sh" & )
  fi
  sleep 3
  say "--- case $name (hosting=$hosting render-busy=$busy swallow-enter=$sw) target=$target"
  say "$(cat "$d/submitted.log.env" 2>/dev/null)"
  say "native agent_status (raw herdr agent get): $(fm_backend_herdr_cli "$SESSION" agent get "$PANE" | jq -r .result.agent.agent_status)"
  say "pane process-state: $(fm_backend_herdr_pane_process_state "$SESSION" "$PANE"); adapter busy_state from outside the pane: $(env -u HERDR_ENV -u HERDR_PANE_ID bash -c ". '$DAEMON'; fm_backend_source herdr; fm_backend_busy_state herdr '$target'")"
  echo "needs-decision: live-$name pick A or B" > "$d/state/live-c1.status"
  sleep "${WAIT:-10}"
  say "submitted lines:"; sed 's/^/    /' "$d/submitted.log"
  say "buffered escalations: $(wc -c < "$d/state/.subsuper-escalations" 2>/dev/null || echo 0) bytes; wedge marker: $([ -e "$d/state/.subsuper-inject-wedged" ] && echo present || echo absent)"
  say "daemon log (inject-related):"; grep -iE 'busy|inject|deliver|defer|wedge|escalat' "$d/state/.supervise-daemon.log" 2>/dev/null | tail -6 | sed 's/^/    /'
  say "pane capture:"; fm_backend_herdr_capture "$target" 6 | sed 's/^/    |/'
  CASE_DIR=$d
  afk_exit "$d/state" 2>/dev/null
  [ -f "$d/state/.supervise-daemon.pid" ] && kill "$(cat "$d/state/.supervise-daemon.pid")" 2>/dev/null
}

# S1: self-hosted, idle render, pinned native working -> digest delivered
run_case s1-selfhosted-delivers 0 self 0
if grep -q 'live-s1-selfhosted-delivers' "$CASE_DIR/submitted.log" && [ ! -s "$CASE_DIR/state/.subsuper-escalations" ]; then
  result PASS "self-hosted daemon delivered the escalation despite native working"; else result FAIL "self-hosted daemon did not deliver"; fi

[ -n "${ONLY_S1:-}" ] && exit $RC
# S2: same pane shape, daemon in its own terminal -> native busy stays conclusive
run_case s2-terminal-hosted-defers 0 terminal 0
if ! grep -q 'live-s2' "$CASE_DIR/submitted.log" && [ -s "$CASE_DIR/state/.subsuper-escalations" ]; then
  result PASS "terminal-hosted daemon still defers on native working and keeps the buffer"; else result FAIL "terminal-hosted daemon injected into a native-busy pane"; fi

# S3: self-hosted, real mid-turn render -> still defers
run_case s3-selfhosted-midturn-defers 1 self 0
if ! grep -q 'live-s3' "$CASE_DIR/submitted.log" && [ -s "$CASE_DIR/state/.subsuper-escalations" ]; then
  result PASS "self-hosted daemon still defers while the rendered busy signature shows a live turn"; else result FAIL "self-hosted daemon injected mid-turn"; fi

# S4: self-hosted, every Enter swallowed -> not discarded as delivered; wedge raised
WAIT=16 run_case s4-selfhosted-swallowed-enter 0 self 1 "FM_MAX_DEFER_SECS=3"
if ! grep -q 'live-s4' "$CASE_DIR/submitted.log" && [ -s "$CASE_DIR/state/.subsuper-escalations" ] && [ -s "$CASE_DIR/state/.subsuper-inject-wedged" ]; then
  result PASS "swallowed self-hosted submit keeps the buffer and raises the wedge marker"; else result FAIL "swallowed self-hosted submit was lost or wedge not raised"; fi

exit $RC

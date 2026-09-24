#!/usr/bin/env bash
# Live drive: real fm-supervise-daemon.sh + its real fm-watch.sh child + real
# fm-procevent.sh reconcile, injecting into a real tmux composer pane on a
# private socket. Seeded with the board result the real Lavish board produced.
set -u
ROOT=/Users/agardner/.no-mistakes/worktrees/c272d8f3fc4c/01M39CBJF6X8YJ1DKEAPD5YGSR
LAVLAB=$(cat /tmp/fm-lavish-lab.path)
SID=lavish-ce9f6cc1be07a770
DAEMON="$ROOT/bin/fm-supervise-daemon.sh"
REAL_TMUX=$(command -v tmux); SOCKET="fm-lab-board-$$"
H=$(mktemp -d /tmp/fm-lab-daemon.XXXXXX); H=$(cd -P "$H" && pwd -P)
S="$H/state"; mkdir -p "$S" "$H/data" "$H/config"; chmod 700 "$S"
cp "$ROOT/.tasks.toml" "$H/.tasks.toml"; printf '## In flight\n\n## Queued\n\n## Done\n' > "$H/data/backlog.md"
LOG="$H/submitted.log"; : > "$LOG"
note() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
cleanup() { [ -z "${DPID:-}" ] || { kill "$DPID" 2>/dev/null; wait "$DPID" 2>/dev/null; }; pkill -f "$H" 2>/dev/null; "$REAL_TMUX" -L "$SOCKET" kill-server 2>/dev/null; rm -rf "$H"; }
trap cleanup EXIT
. "$DAEMON"   # for afk_enter / FM_INJECT_MARK

"$REAL_TMUX" -L "$SOCKET" new-session -d -s supervisor -x 220 -y 50
PANE=$("$REAL_TMUX" -L "$SOCKET" display-message -p -t supervisor '#{pane_id}')
# Composer loop copied from tests/fm-afk-inject-e2e.test.sh: logs each submitted line.
sed -n '/^LOOP_SCRIPT="\$STATE_DIR\/supervisor-loop.sh"/,/^LOOP$/p' "$ROOT/tests/fm-afk-inject-e2e.test.sh" | sed '1,2d;$d' > "$H/loop.sh"
chmod +x "$H/loop.sh"
"$REAL_TMUX" -L "$SOCKET" send-keys -t "$PANE" "bash '$H/loop.sh' '$LOG'" Enter; sleep 1
mkdir -p "$H/shim"; printf '#!/usr/bin/env bash\nexec "%s" -L "%s" "$@"\n' "$REAL_TMUX" "$SOCKET" > "$H/shim/tmux"; chmod +x "$H/shim/tmux"

seed() {  # <seq>: the real captured board result, as the runner leaves it
  mkdir -p "$S/procevent-inbox" "$S/procevent"; chmod 700 "$S/procevent-inbox" "$S/procevent"
  cp "$LAVLAB/state/procevent-inbox/$SID.1.result" "$S/procevent-inbox/$SID.$1.result"
  printf 'lavish\n' > "$S/procevent-inbox/$SID.$1.adapter"
  chmod 600 "$S/procevent-inbox/$SID.$1."*
}
type_draft() { "$REAL_TMUX" -L "$SOCKET" send-keys -t "$PANE" -l "$1"; }
digests() { grep -c "procevent lavish $SID $1" "$LOG" 2>/dev/null || true; }

afk_enter "$S"
PATH="$H/shim:$PATH" FM_HOME="$H" FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$S" FM_DATA_OVERRIDE="$H/data" \
  FM_CONFIG_OVERRIDE="$H/config" FM_PROCEVENT_CLAIM_ROOT="$H/claims" \
  FM_SUPERVISOR_TARGET="$PANE" FM_SUPERVISOR_BACKEND=tmux FM_ESCALATE_BATCH_SECS=90 \
  FM_HOUSEKEEPING_TICK=1 FM_POLL=1 FM_SIGNAL_GRACE=1 FM_HEARTBEAT=999999 FM_CHECK_INTERVAL=999999 \
  FM_INJECT_CONFIRM_SLEEP=0.3 FM_INJECT_CONFIRM_RETRIES=5 FM_STALE_ESCALATE_SECS=999999 FM_MAX_DEFER_SECS=600 \
  "$DAEMON" > "$H/daemon.out" 2> "$H/daemon.err" &
DPID=$!
for _ in $(seq 30); do [ -f "$S/.supervise-daemon.pid" ] && break; sleep 0.2; done
note "daemon up (pid $DPID), FM_ESCALATE_BATCH_SECS=90, FM_POLL=1, re-announce interval default 300s"

echo "=== Scenario: composer guard holds a board answer while the captain types"
type_draft "captain is typing a reply"
seed 1; T0=$(date +%s); note "board result $SID 1 captured (unhandled)"
sleep 10
note "after 10s (~10 watcher cycles): digests delivered for seq 1 = $(digests 1); buffered copies = $(grep -c "$SID 1" "$S/.subsuper-escalations" 2>/dev/null || echo 0); wake-queue announcements = $(grep -c "procevent:$SID:1" "$S/.wake-queue" 2>/dev/null || echo 0)"
"$REAL_TMUX" -L "$SOCKET" send-keys -t "$PANE" Enter; T1=$(date +%s)
note "captain submitted their own line"
for _ in $(seq 40); do [ "$(digests 1)" -ge 1 ] && break; sleep 0.25; done
note "board answer digest delivered $(( $(date +%s) - T1 ))s after the composer emptied ($(( $(date +%s) - T0 ))s after capture; batch window is 90s)"
echo "=== Scenario: one unhandled result is not re-escalated on every watcher cycle"
sleep 15
note "after 15 more watcher cycles: digests for seq 1 = $(digests 1); wake-queue announcements = $(grep -c "procevent:$SID:1" "$S/.wake-queue" 2>/dev/null || echo 0)"
echo "=== Scenario: a result handled while its delivery waits is never delivered"
type_draft "second draft"
seed 2; note "board result $SID 2 captured while the captain types"
sleep 4; note "buffered: $(grep -c "$SID 2" "$S/.subsuper-escalations" 2>/dev/null || echo 0)"
FM_HOME="$H" FM_STATE_OVERRIDE="$S" FM_PROCEVENT_CLAIM_ROOT="$H/claims" "$ROOT/bin/fm-procevent.sh" handled "$SID" 2
"$REAL_TMUX" -L "$SOCKET" send-keys -t "$PANE" Enter; note "captain submitted; composer empty"
sleep 8
note "digests for seq 2 = $(digests 2)"
echo "=== Submitted lines in the supervisor pane (verbatim, text column):"
cut -f2,3 "$LOG"
echo "=== daemon log lines about escalation:"
grep -iE 'escalat|defer|dropped' "$S"/.supervise-daemon.log "$H/daemon.err" 2>/dev/null | tail -20
"$REAL_TMUX" -L "$SOCKET" capture-pane -p -t "$PANE" | grep -v '^$' | tail -8

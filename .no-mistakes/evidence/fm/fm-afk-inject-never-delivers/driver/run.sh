#!/usr/bin/env bash
# run.sh <tree-root> <label>
# Drives the REAL away-mode daemon (bin/fm-supervise-daemon.sh) over the REAL
# herdr adapter. Nothing in firstmate is mocked; only the external herdr 0.8.0
# CLI is replaced by a herdr-shaped fake pane (driver/fake-herdr), because the
# real herdr CLI cannot be driven here (herdr status --json hangs, a documented
# pre-existing environment defect).
set -u
ROOT=$1; LABEL=$2
BIN=$(cd "$(dirname "$0")" && pwd)
echo "================ $LABEL ================"

setup() {  # <scenario> <footer> [swallow]
  D=$(mktemp -d "${TMPDIR:-/tmp}/fm-e2e.XXXXXX")
  export FAKE_HERDR_STATE="$D/pane"; mkdir -p "$FAKE_HERDR_STATE" "$D/state" "$D/fakebin"
  : > "$FAKE_HERDR_STATE/buffer"; : > "$FAKE_HERDR_STATE/submitted.log"; : > "$FAKE_HERDR_STATE/cli.log"
  printf 'working\n' > "$FAKE_HERDR_STATE/agent_status"   # pinned by the daemon's own background job
  printf '%s\n' '  crew c1: pushed the branch' '* Churned for 2m 17s' > "$FAKE_HERDR_STATE/transcript"
  printf '%s' "$2" > "$FAKE_HERDR_STATE/footer"
  [ "${3:-}" = swallow ] && : > "$FAKE_HERDR_STATE/swallow-all"
  cp "$BIN/fake-herdr" "$D/fakebin/herdr"
}

env_for() {
  PATH="$D/fakebin:$PATH" \
  HERDR_ENV=1 HERDR_PANE_ID=w1:p2 HERDR_SESSION=default TMUX_PANE='' \
  FM_STATE_OVERRIDE="$D/state" FM_DAEMON_PRIMARY_HARNESS=claude \
  FM_SUPERVISOR_BACKEND=herdr FM_SUPERVISOR_TARGET=default:w1:p2 \
  FM_INJECT_CONFIRM_RETRIES=2 FM_INJECT_CONFIRM_SLEEP=0.2 \
  bash -c ". \"\$0/bin/fm-supervise-daemon.sh\"; $1" "$ROOT"
}

# --- S3: an escalation raised in away mode on a self-hosted daemon -----------
setup s3 ''
env_for 'afk_enter "$FM_STATE_OVERRIDE"; if inject_msg "three jobs parked awaiting decisions" "$FM_STATE_OVERRIDE"; then echo "inject_msg: DELIVERED"; else echo "inject_msg: DEFERRED (not delivered)"; fi' 2>&1 | sed 's/^/  /'
echo "  captain pane received: $(cat "$FAKE_HERDR_STATE/submitted.log" | sed 's/^/>> /' | tr '\n' '|')"
S3_LOG=$FAKE_HERDR_STATE/submitted.log

# --- S4 (adversarial): the harness really IS mid-turn -----------------------
setup s4 'Cogitating... (12s - esc to interrupt)
'
env_for 'afk_enter "$FM_STATE_OVERRIDE"; if inject_msg "three jobs parked awaiting decisions" "$FM_STATE_OVERRIDE"; then echo "inject_msg: DELIVERED"; else echo "inject_msg: DEFERRED (not delivered)"; fi' 2>&1 | sed 's/^/  /'
echo "  captain pane received: $(cat "$FAKE_HERDR_STATE/submitted.log" | tr '\n' '|')"

# --- S5 (adversarial): every Enter is swallowed -----------------------------
setup s5 '' swallow
env_for 'escalate_add "$FM_STATE_OVERRIDE" "event A: worker died"; afk_enter "$FM_STATE_OVERRIDE"; : > "$FM_STATE_OVERRIDE/.subsuper-inject-wedged"; if escalate_flush "$FM_STATE_OVERRIDE"; then echo "escalate_flush: reported FLUSHED"; else echo "escalate_flush: reported NOT flushed"; fi; if [ -s "$FM_STATE_OVERRIDE/.subsuper-escalations" ]; then echo "buffer: PRESERVED ($(cat "$FM_STATE_OVERRIDE/.subsuper-escalations" | tr "\n" " "))"; else echo "buffer: TRUNCATED (escalation discarded)"; fi; if [ -e "$FM_STATE_OVERRIDE/.subsuper-inject-wedged" ]; then echo "wedge marker: RAISED"; else echo "wedge marker: CLEARED"; fi' 2>&1 | sed 's/^/  /'
echo "  captain pane received: $(cat "$FAKE_HERDR_STATE/submitted.log" | tr '\n' '|')"

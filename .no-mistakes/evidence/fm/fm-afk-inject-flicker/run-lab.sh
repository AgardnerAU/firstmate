#!/usr/bin/env bash
set -u
export FM_HERDR_LAB_FLEET_SESSION=fm-remote
W={run-worktree}
E=~/.no-mistakes/evidence/01M7EJJGR49T623K2DQ4X445AV
HERDR_LAB_HELPER=$W/bin/fm-herdr-lab.sh
LAB_HOME_HELPER=$W/bin/fm-lab-home.sh
export HERDR_LAB_HELPER
HERDR_LAB_SESSION=$("$HERDR_LAB_HELPER" name nm-test-5805) || exit 1
export HERDR_LAB_SESSION
FM_HOME=$(mktemp -d /tmp/fm-nmtest-lab.XXXXXX) || exit 1
export FM_HOME
LAB_TMUX_DIR=
cleanup() {
  rc=$?
  trap - EXIT
  socket="$LAB_TMUX_DIR/tmux-$(id -u)/default"
  if [ -n "$LAB_TMUX_DIR" ] && [ -S "$socket" ]; then tmux -S "$socket" kill-server || rc=1; fi
  "$LAB_HOME_HELPER" teardown "$FM_HOME" || rc=1
  "$HERDR_LAB_HELPER" teardown "$HERDR_LAB_SESSION" || rc=1
  printf 'teardown rc=%s\n' "$rc"
  exit "$rc"
}
trap cleanup EXIT
"$LAB_HOME_HELPER" create "$FM_HOME" >/dev/null || exit 1
LAB_TMUX_DIR=$("$LAB_HOME_HELPER" tmux-dir "$FM_HOME") || exit 1
export TMUX_TMPDIR="$LAB_TMUX_DIR"
"$HERDR_LAB_HELPER" provision "$HERDR_LAB_SESSION" || exit 1
printf 'session=%s\n' "$HERDR_LAB_SESSION"
cd "$W"
PATH=/usr/bin:/bin timeout 180 bash tests/fm-afk-launch.test.sh > $E/launch-test.log 2>&1
launch_rc=$?
printf 'launch test exit=%s\n' "$launch_rc"
FM_AFK_INJECT_CLAUDE_LIVE=1 FM_AFK_LIVE_PREPROVISIONED=1 timeout 240 bash tests/fm-afk-inject-claude-live-e2e.test.sh > $E/live-test.log 2>&1
live_rc=$?
printf 'live test exit=%s\n' "$live_rc"
[ "$launch_rc" -eq 0 ] && [ "$live_rc" -eq 0 ]

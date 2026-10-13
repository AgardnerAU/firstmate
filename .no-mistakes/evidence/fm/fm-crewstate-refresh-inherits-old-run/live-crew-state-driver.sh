#!/usr/bin/env bash
# Live driver: the real bin/fm-crew-state.sh (with the real fm-busy-event.sh
# semantic busy contract and a real tmux pane on a private lab socket) in a
# disposable marked lab FM_HOME. The worker worktree is a disposable real git
# repo on the refresh branch. The no-mistakes CLI is a stand-in that serves
# one finished run record (the gate forbids `no-mistakes init`, so the real
# daemon cannot serve a disposable repo). Forge reads are disabled
# (FM_CREW_STATE_NO_FORGE=1) so no network or credentials are touched.
set -u
ROOT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
cleanup() { TMUX_TMPDIR="$LAB/tmux" tmux kill-server 2>/dev/null; rm -rf "$LAB"; }
trap cleanup EXIT
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/tmux" "$LAB/fakebin" "$LAB/wt"
BR=fm/fm-crewstate-refresh-inherits-old-run

git -C "$LAB/wt" init -q
git -C "$LAB/wt" -c user.name=lab -c user.email=lab@example.invalid commit -q --allow-empty -m init
git -C "$LAB/wt" checkout -q -b "$BR"
git -C "$LAB/wt" update-ref refs/remotes/origin/main "$(git -C "$LAB/wt" rev-parse HEAD)"
HEAD_SHA=$(git -C "$LAB/wt" rev-parse HEAD)
SHORT=$(git -C "$LAB/wt" rev-parse --short=8 HEAD)

cat > "$LAB/fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "axi ") printf '%s\n' "$LAB_AXI_HOME" ;;
  "axi status") printf '%s\n' "$LAB_AXI_STATUS" ;;
  "axi logs") printf '%s\n' "${LAB_CI_LOGS:-}" ;;
  "daemon "*) echo 'daemon running (pid 4242)' ;;
esac
exit 0
SH
chmod +x "$LAB/fakebin/no-mistakes"

ulid_at() {  # <epoch-seconds>
  local ms=$(($1 * 1000)) a=0123456789ABCDEFGHJKMNPQRSTVWXYZ t='' i
  for i in 1 2 3 4 5 6 7 8 9 10; do t="${a:$((ms % 32)):1}$t"; ms=$((ms / 32)); done
  printf '%sABCDEFGHJKMNPQRS' "$t"
}
serve_run() {  # <run-id> <outcome>
  export LAB_AXI_STATUS="run:
  id: \"$1\"
  branch: $BR
  status: completed
  head: \"$HEAD_SHA\"
  pr: \"https://github.com/kunchenguid/firstmate/pull/6245\"
  findings: none
outcome: $2"
  export LAB_AXI_HOME="count: 1 of 1 total
runs[1]{id,branch,status,head,pr}:
  \"$1\",$BR,completed,$SHORT,\"https://github.com/kunchenguid/firstmate/pull/6245\""
}
export TMUX_TMPDIR="$LAB/tmux"
tmux new-session -d -s fm -n fm-boot 'sleep 600'
meta() {  # <id> <line>...
  local id=$1; shift
  tmux new-window -d -t fm: -n "fm-$id" 'sleep 600'
  # pr= is appended last, as the task record's PR identity contract requires.
  { printf 'window=fm:fm-%s\nworktree=%s\nkind=ship\nharness=claude\nbranch=%s\n' "$id" "$LAB/wt" "$BR"
    printf '%s\n' "$@"
    printf 'pr=https://github.com/kunchenguid/firstmate/pull/6245\n'; } > "$LAB/state/$id.meta"
}
busy() { local g; g=$("$ROOT/bin/fm-busy-event.sh" arm "$LAB/state" "$1"); "$ROOT/bin/fm-busy-event.sh" apply "$LAB/state" "$1" busy --gen "$g" --source claude-hook --event user-prompt-submit >/dev/null; }
idle() { local g; g=$("$ROOT/bin/fm-busy-event.sh" arm "$LAB/state" "$1"); "$ROOT/bin/fm-busy-event.sh" apply "$LAB/state" "$1" idle --gen "$g" --source claude-hook --event stop >/dev/null 2>&1 || true; }
crew() {
  echo "\$ fm-crew-state.sh $1"
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
    -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
    PATH="$LAB/fakebin:$PATH" FM_HOME="$LAB" FM_CREW_STATE_NO_FORGE=1 "$ROOT/bin/fm-crew-state.sh" "$1"
}
now=$(date +%s)
OLD=$(ulid_at $((now - 3600)))   # an earlier task's run, finished an hour ago
NEW=$(ulid_at $((now + 120)))    # this task's own run, created after it started

echo "## S1 refresh task (task_started=now) over an earlier task's FINISHED PASSED run $OLD on the same branch+head; worker busy"
serve_run "$OLD" passed
meta s1 "task_started=$now"; busy s1
crew s1

echo; echo "## S2 same earlier run; worker idle with its own status log line"
meta s2 "task_started=$now"; idle s2
printf 'working [at=%s]: resolving merge conflicts\n' "$now" > "$LAB/state/s2.status"
crew s2

echo; echo "## S3 this task's own run $NEW (created after task_started) finished passed: done, PR state names its source"
serve_run "$NEW" passed
meta s3 "task_started=$now"
crew s3

echo; echo "## S4 relaunched task: task_started an hour before, spawn_gen minted now; earlier-incarnation run $OLD still attributed"
serve_run "$(ulid_at $((now - 600)))" passed
meta s4 "task_started=$((now - 3600))" "spawn_gen=s$now.1.1"
crew s4

echo; echo "## S5 legacy record (no task_started) bounded by spawn_gen=now: earlier run $OLD not attributed"
serve_run "$OLD" passed
meta s5 "spawn_gen=s$now.1.1"; busy s5
crew s5

echo; echo "## S6 adversarial: run created 1s before task start (same second-ish) - still refused"
serve_run "$(ulid_at $((now - 1)))" passed
meta s6 "task_started=$now"; busy s6
crew s6

echo; echo "## S7 adversarial: run id that is not a ULID while a task start is recorded - refused"
serve_run "01RUN" passed
meta s7 "task_started=$now"; busy s7
crew s7

echo; echo "## S8 own run in ci monitoring that reports no CI checks (held at action_required) - waiting, not green"
export LAB_AXI_STATUS="run:
  id: \"$NEW\"
  branch: $BR
  status: running
  head: \"$HEAD_SHA\"
  pr: \"https://github.com/kunchenguid/firstmate/pull/6245\"
  findings: none
  steps[4]{step,status,findings,duration_ms}:
    intent,completed,0,0
    review,completed,0,0
    push,completed,0,0
    ci,running,0,0"
export LAB_AXI_HOME="$LAB_AXI_STATUS"
export LAB_CI_LOGS="no CI checks reported - still monitoring until merged or closed"
meta s8 "task_started=$now"
crew s8
echo; echo "## lab torn down on exit"

#!/usr/bin/env bash
# Live drive of the real bin/fm-crew-state.sh against a disposable lab home,
# a real git worktree, a real tmux pane on a private lab socket, and the real
# fm-busy-event.sh busy contract. no-mistakes and gh are served by local
# stand-ins (the validation daemon and the forge are external services this
# gate must not initialise or contact).
set -u
REPO=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$REPO/bin/fm-lab-home.sh" create "$LAB" >/dev/null
TMUXD=$("$REPO/bin/fm-lab-home.sh" tmux-dir "$LAB")
cleanup() { TMUX_TMPDIR="$TMUXD" tmux -L fm-lab kill-server 2>/dev/null; "$REPO/bin/fm-lab-home.sh" teardown "$LAB" >/dev/null 2>&1; rm -rf "$LAB"; }
trap cleanup EXIT
FB=$LAB/fakebin; NM=$LAB/nm; mkdir -p "$FB" "$NM"
cat > "$FB/no-mistakes" <<'SH'
#!/usr/bin/env bash
NM=$FM_LAB_NM
case "$1" in
  axi) shift
    if [ $# = 0 ]; then if [ -s "$NM/home" ]; then cat "$NM/home"; else cat "$NM/status" 2>/dev/null; fi; exit 0; fi
    case "$1" in
      status) cat "$NM/status" 2>/dev/null ;;
      logs) cat "$NM/cilog" 2>/dev/null ;;
    esac ;;
  runs) cat "$NM/runs" 2>/dev/null ;;
  daemon) echo 'daemon running (pid 1)' ;;
esac
exit 0
SH
cat > "$FB/gh" <<'SH'
#!/usr/bin/env bash
if [ "$1 $2" = "api graphql" ]; then
  n=1; for a in "$@"; do case "$a" in number=*) n=${a#number=} ;; esac; done
  cat "$FM_LAB_NM/pr$n" 2>/dev/null || { echo state=OPEN; echo merged=false; }
  exit 0
fi
exit 1
SH
chmod +x "$FB"/*
ulid_at() { local ms=$(($1*1000)) a=0123456789ABCDEFGHJKMNPQRSTVWXYZ t='' i; for i in 1 2 3 4 5 6 7 8 9 10; do t="${a:$((ms%32)):1}$t"; ms=$((ms/32)); done; printf '%sABCDEFGHJKMNPQRS' "$t"; }

WT=$LAB/wt; mkdir -p "$WT"
git -C "$WT" init -q; git -C "$WT" -c user.name=lab -c user.email=lab@example.invalid commit -q --allow-empty -m init
git -C "$WT" checkout -q -b fm/refresh
git -C "$WT" update-ref refs/remotes/origin/main "$(git -C "$WT" rev-parse HEAD)"
HEAD_FULL=$(git -C "$WT" rev-parse HEAD); SHORT=$(git -C "$WT" rev-parse --short=8 HEAD)

TMUX_TMPDIR="$TMUXD" tmux -L fm-lab new-session -d -s fm -n fm-refresh -c "$WT" 'sleep 100000'
SOCK=$(TMUX_TMPDIR="$TMUXD" tmux -L fm-lab display-message -p -t fm:fm-refresh '#{socket_path}')
NOW=$(date +%s)

crew() { env -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u FM_ROOT_OVERRIDE \
  FM_HOME="$LAB" FM_LAB_NM="$NM" TMUX="$SOCK,1,0" TMUX_TMPDIR="$TMUXD" PATH="$FB:$PATH" "$REPO/bin/fm-crew-state.sh" "$1"; }
meta() { printf '%s\n' "window=fm:fm-refresh" "worktree=$WT" "kind=ship" "harness=claude" "$@" > "$LAB/state/refresh.meta"; }
passed_run() { # <run-id> <outcome> [extra]
  cat > "$NM/status" <<EOF
run:
  id: "$1"
  branch: fm/refresh
  status: completed
  head: "$HEAD_FULL"
  pr: "https://github.com/o/r/pull/1"
  findings: none
outcome: $2
${3:-}
EOF
  printf 'count: 1 of 1 total\nruns[1]{id,branch,status,head,pr}:\n  "%s",fm/refresh,completed,%s,"https://github.com/o/r/pull/1"\n' "$1" "$SHORT" > "$NM/home"
}
busy() { local g; g=$("$REPO/bin/fm-busy-event.sh" arm "$LAB/state" refresh); "$REPO/bin/fm-busy-event.sh" apply "$LAB/state" refresh "$1" --gen "$g" --source claude-hook --event "$2" >/dev/null; }
show() { printf '\n### %s\n$ fm-crew-state.sh refresh\n%s\n' "$1" "$(crew refresh)"; }
reset_pr() { rm -f "$NM"/pr* "$NM/cilog" "$LAB/state/refresh.status"; }

echo "lab home: $LAB  (real tmux pane on private socket, head $SHORT)"
OLD=$(ulid_at $((NOW-3600))); NEWR=$(ulid_at $((NOW+60)))
echo "earlier task's run id: $OLD (created $(date -r $((NOW-3600)) '+%H:%M:%S')); task_started=$NOW ($(date -r $NOW '+%H:%M:%S'))"

echo; echo "== S1 refresh worker busy over an earlier task's passed run on the same branch+head =="
meta "task_started=$NOW"; passed_run "$OLD" passed; busy busy user-prompt-submit
show "busy refresh worker"

echo; echo "== S2 refresh worker idle, status log says it is resolving conflicts =="
busy idle stop; printf 'working [at=%s]: resolving merge conflicts\n' "$NOW" > "$LAB/state/refresh.status"
show "idle refresh worker with status log"

echo; echo "== S2b legacy runs ledger route: earlier row only =="
: > "$NM/home"; printf '  completed fm/refresh %s %s https://github.com/o/r/pull/1\n' "$SHORT" "$(date -r $((NOW-3600)) '+%Y-%m-%d %H:%M')" > "$NM/runs"
sed -i '' "s/$OLD/01OTHERRUNIDNOTOURS0000000/" "$NM/status"; sed -i '' 's/branch: fm\/refresh/branch: fm\/another/; s/status: completed/status: running/' "$NM/status"
show "coarse ledger, earlier row"
rm -f "$NM/runs"; reset_pr

echo; echo "== S3 control: this task's own run created after it started =="
meta "task_started=$NOW"; passed_run "$NEWR" passed
show "own run"

echo; echo "== S4 relaunched task keeps its earlier-incarnation run (task_started carried) =="
meta "task_started=$((NOW-3600))" "spawn_gen=s$NOW.1.1"; passed_run "$(ulid_at $((NOW-600)))" passed
show "relaunch"

echo; echo "== S5 merged claim needs the recorded pr= identity checked against the forge =="
printf 'state=MERGED\nmerged=true\n' > "$NM/pr1"; printf 'state=OPEN\nmerged=false\n' > "$NM/pr2"
meta; passed_run "$NEWR" passed
show "forge says PR 1 merged, no recorded pr="
meta "pr=https://github.com/o/r/pull/2"
show "recorded pr=2 (open), run PR is 1 (merged)"
meta "pr=https://github.com/o/r/pull/1"
show "recorded pr=1 merged on forge"
printf 'state=OPEN\nmerged=false\n' > "$NM/pr1"
show "recorded pr=1 open on forge (AGFloorPlanner 3000 shape)"
reset_pr

echo; echo "== S6 newer worker status line vs a finished run =="
meta "task_started=$((NOW-3600))"; passed_run "$(ulid_at $((NOW-600)))" passed
printf 'working [at=%s]: rebasing after upstream conflict\n' "$NOW" > "$LAB/state/refresh.status"
show "status written after run start"
printf 'working [at=%s]: setting up before validation\n' "$((NOW-1200))" > "$LAB/state/refresh.status"
show "status written before run start"
reset_pr

echo; echo "== S7 deliberate abort vs failure =="
meta
cat > "$NM/status" <<EOF
run:
  id: "$NEWR"
  branch: fm/refresh
  status: cancelled
  head: "$HEAD_FULL"
  pr: ""
  findings: none
outcome: cancelled
error: "cancelled: aborted by user"
EOF
: > "$NM/home"
show "aborted by user"
sed -i '' 's/aborted by user/superseded by new push/' "$NM/status"
show "superseded by new push"
cat > "$NM/status" <<EOF
run:
  id: "$NEWR"
  branch: fm/refresh
  status: completed
  head: "$HEAD_FULL"
  pr: ""
  findings: none
outcome: failed
EOF
show "genuine failure"

echo; echo "== S8 Greptile-only checks pass / CI held at action_required: never green =="
meta; passed_run "$NEWR" checks-passed
show "run outcome checks-passed"
cat > "$NM/status" <<EOF
run:
  id: "$NEWR"
  branch: fm/refresh
  status: ci
  head: "$HEAD_FULL"
  pr: "https://github.com/o/r/pull/2"
  findings: none
EOF
: > "$NM/home"
printf 'all CI checks passed - still monitoring until merged or closed\n' > "$NM/cilog"
show "ci log: all CI checks passed (only Greptile Review reported)"
printf 'no CI checks reported - still monitoring\n' > "$NM/cilog"
show "ci log: no CI checks reported (CI held at action_required)"
rm -f "$NM/cilog"
passed_run "$NEWR" passed-with-override 'ci_override_reason: "live checks for https://github.com/o/r/pull/1: no checks reported"'
show "passed-with-override, no checks reported"
echo; echo "lab torn down on exit"

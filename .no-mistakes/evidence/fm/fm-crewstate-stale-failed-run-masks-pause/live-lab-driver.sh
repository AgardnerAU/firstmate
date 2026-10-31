#!/usr/bin/env bash
# Live lab driver: real bin/fm-crew-state.sh -> real bin/fm-inactive-reconcile.sh
# in a disposable fm-lab-home, with only the external no-mistakes/tmux CLIs faked.
set -u
ROOT=$1; DRV=$2
TMP_ROOT=$DRV/tmp; mkdir -p "$TMP_ROOT"
# shellcheck disable=SC1090
source <(sed -n '/^make_fakebin() {/,/^}/p; /^reset_fakes() {/,/^}/p; /^run_failed() {/,/^}/p; /^run_failed_with_pr() {/,/^}/p; /^ledger_stamp_minutes_ago() {/,/^}/p' "$ROOT/tests/fm-crew-state.test.sh")
export GIT_AUTHOR_NAME=lab GIT_AUTHOR_EMAIL=lab@example.invalid GIT_COMMITTER_NAME=lab GIT_COMMITTER_EMAIL=lab@example.invalid
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
trap 'rm -rf "$LAB"' EXIT
FB=$(make_fakebin "$LAB")
echo "lab home: $LAB (marked: $(ls "$LAB" | tr '\n' ' '))"

scenario() { # <name> <id> <status-log> ; uses FM_FAKE_* already set
  local name=$1 id=$2 log=$3 wt="$LAB/projects/$2" line
  echo; echo "=== $name ==="
  printf '%s\n' "$log" > "$LAB/state/$id.status"
  local old=$(( $(date +%s) - 300 ))
  touch -d "@$old" "$LAB/state/$id.meta" "$LAB/state/$id.status"; : > "$LAB/state/$id.turn-ended"; touch -d "@$old" "$LAB/state/$id.turn-ended"
  echo "status log: $log"
  echo "ledger (no-mistakes runs):"; printf '%s\n' "$FM_FAKE_RUNS_LIST" | sed 's/^/    /'
  line=$(env -u FM_ROOT_OVERRIDE PATH="$FB:$PATH" FM_HOME="$LAB" FM_STATE_OVERRIDE="$LAB/state" FM_CREW_STATE_NO_FORGE=1 "$ROOT/bin/fm-crew-state.sh" "$id")
  echo "fm-crew-state.sh $id -> $line"
  env -u FM_ROOT_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE \
    PATH="$FB:$PATH" FM_HOME="$LAB" FM_STATE_OVERRIDE="$LAB/state" FM_INACTIVE_RECONCILE_SECS=60 \
    "$ROOT/bin/fm-inactive-reconcile.sh" scan --startup >/dev/null 2>"$DRV/recon.err" || { echo "reconcile rc=$?"; cat "$DRV/recon.err"; }
  echo "wake queue entries for $id:"; grep -F "inactive-outcome:" "$LAB/state/.wake-queue" 2>/dev/null | grep -F "$id" | sed 's/^/    /' || echo "    (none queued)"
}

new_crew() { # <id> <branch>
  local id=$1 br=$2 wt="$LAB/projects/$1"
  mkdir -p "$wt"; git -C "$wt" init -q; git -C "$wt" commit -q --allow-empty -m init
  git -C "$wt" checkout -q -b "$br"
  git -C "$wt" update-ref refs/remotes/origin/main "$(git -C "$wt" rev-parse HEAD)"
  FM_FAKE_RUN_HEAD=$(git -C "$wt" rev-parse HEAD); export FM_FAKE_RUN_HEAD
  SHORT=$(git -C "$wt" rev-parse --short=8 HEAD)
  printf '%s\n' "window=fm:fm-$id" "worktree=$wt" "project=$wt" harness=codex kind=ship mode=no-mistakes yolo=off "spawn_gen=s$RANDOM" > "$LAB/state/$id.meta"
}

# S1: genuine failure, newest ledger row is the same run -> failed with its own PR
reset_fakes; new_crew s1 fm/s1
FM_FAKE_AXI_STATUS="$(run_failed_with_pr fm/s1 https://github.com/o/r/pull/11)"
FM_FAKE_RUNS_LIST="  failed     fm/s1 ${SHORT}  $(ledger_stamp_minutes_ago 30)  https://github.com/o/r/pull/11"
scenario "S1 genuine failed run keeps its own PR" s1 "working: validating"
rm -f "$LAB/state/s1."*

# S2: stale failed run, newer CANCELLED ledger row -> unknown, no captain outcome
reset_fakes; new_crew s2 fm/s2
FM_FAKE_AXI_STATUS="$(run_failed_with_pr fm/s2 https://github.com/o/r/pull/21)"
FM_FAKE_RUNS_LIST="$(printf '  cancelled  fm/s2 f0f0f0f0  %s\n  failed     fm/s2 %s  %s  https://github.com/o/r/pull/21' "$(ledger_stamp_minutes_ago 10)" "$SHORT" "$(ledger_stamp_minutes_ago 40)")"
scenario "S2 newer cancelled row reads unknown (cancellation-as-unknown)" s2 "paused: waiting on captain"
rm -f "$LAB/state/s2."*

# S3: stale failed run, newer unbindable COMPLETED row; crew wrote done -> unknown, never done/failed
reset_fakes; new_crew s3 fm/s3
FM_FAKE_AXI_STATUS="$(run_failed fm/s3)"
FM_FAKE_RUNS_LIST="$(printf '  completed  fm/s3 f0f0f0f0  %s  https://github.com/o/r/pull/31\n  failed     fm/s3 %s  %s' "$(ledger_stamp_minutes_ago 10)" "$SHORT" "$(ledger_stamp_minutes_ago 40)")"
scenario "S3 newer unbindable completed row is never published as success or failure" s3 "done: PR https://github.com/o/r/pull/31 merged"
rm -f "$LAB/state/s3."*

# S4: stale failed run masking a later declared pause (the branch's namesake bug) -> unknown, no failed outcome
reset_fakes; new_crew s4 fm/s4
FM_FAKE_AXI_STATUS="$(run_failed fm/s4)"
FM_FAKE_RUNS_LIST="$(printf '  running    fm/s4 f0f0f0f0  %s\n  failed     fm/s4 %s  %s' "$(ledger_stamp_minutes_ago 5)" "$SHORT" "$(ledger_stamp_minutes_ago 40)")"
scenario "S4 stale failed run with a newer live run does not surface as failed" s4 "paused: awaiting captain on scope"
rm -f "$LAB/state/s4."*

# S5/S6: no run; crew status-log ready signal in GitLab / Gerrit shape -> outcome keeps review URL
for f in "gitlab|PR https://gitlab.example/group/sub/project/-/merge_requests/8 checks green" "gerrit|PR https://gerrit.example/c/group/project/+/4201 published for review" "prose|implementation complete, see PR https://github.com/o/r/pull/77"; do
  n=${f%%|*}; note=${f#*|}
  reset_fakes; new_crew "s-$n" "fm/s-$n"
  FM_FAKE_AXI_STATUS=""; FM_FAKE_RUNS_LIST=""
  sed -i 's/^harness=codex/harness=claude/' "$LAB/state/s-$n.meta"
  [ "$n" != gerrit ] || { sed -i 's/^mode=no-mistakes/mode=direct-PR/' "$LAB/state/s-$n.meta"; printf "%s\n" forge=gerrit pr=https://gerrit.example/c/group/project/+/4201 >> "$LAB/state/s-$n.meta"; }
  gen=$("$ROOT/bin/fm-busy-event.sh" arm "$LAB/state" "s-$n"); "$ROOT/bin/fm-busy-event.sh" apply "$LAB/state" "s-$n" idle --gen "$gen" --source claude-hook --event stop >/dev/null
  scenario "S-$n status-log done outcome" "s-$n" "done: $note"
  rm -f "$LAB/state/s-$n."*
done
echo; echo "lab removed on exit"

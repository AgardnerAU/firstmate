#!/usr/bin/env bash
# Live lab driver: real bin/fm-crew-state.sh and bin/fm-inactive-reconcile.sh
# (from the worktree under test, or a base-commit export) against a disposable
# marked lab FM_HOME. Only the external `no-mistakes` CLI is replaced, by a stub
# that serves per-scenario recorded TOON / ledger text (the shared daemon is
# never touched).
set -u
REPO=$1          # tree whose bin/ to run
LAB=$2           # marked lab home (already created)
SCEN=$3          # scenario name
ID=crew
BR=fm/lab-demo
WT="$LAB/projects/$ID"
STUB="$LAB/stubbin"; mkdir -p "$STUB" "$LAB/nm/$SCEN" "$LAB/tmux"
cat > "$STUB/no-mistakes" <<'SH'
#!/usr/bin/env bash
d="$FM_LAB_NM/$FM_LAB_SCEN"
case "${1:-}" in
  axi) shift
    if [ "$#" = 0 ]; then cat "$d/axi"; exit 0; fi
    case "$1" in status) cat "$d/axi" ;; logs) : ;; esac ;;
  runs) cat "$d/runs" 2>/dev/null ;;
  daemon) echo '  ● daemon running (pid 4242)' ;;
esac
exit 0
SH
chmod +x "$STUB/no-mistakes"
# Fresh crew worktree + meta for this scenario.
rm -rf "$WT" "$LAB/state"/*; rm -rf "$LAB/state"/.[!.]* 2>/dev/null
mkdir -p "$WT"
git -C "$WT" init -q; git -C "$WT" -c user.name=lab -c user.email=lab@example.invalid commit -q --allow-empty -m init
git -C "$WT" checkout -q -b "$BR"
HEAD_SHA=$(git -C "$WT" rev-parse HEAD); SHORT=${HEAD_SHA:0:8}
git -C "$WT" update-ref refs/remotes/origin/main "$HEAD_SHA"
stamp() { date -d "@$(( $(date +%s) - $1 * 60 ))" '+%Y-%m-%d %H:%M'; }
run_toon() { # <status> <outcome> <pr>
cat <<EOF
run:
  id: "01LABRUNOLD"
  branch: $BR
  status: $1
  head: "$HEAD_SHA"
  pr: "$3"
  findings: none
outcome: $2
EOF
}
STATUS_LINE='working: shipping lab change'
case "$SCEN" in
  stale-failed-newer-live-row)   # the reported masking shape
    run_toon failed failed "" > "$LAB/nm/$SCEN/axi"
    printf '  running    %s f0f0f0f0  %s\n  failed     %s %s  %s\n' "$BR" "$(stamp 5)" "$BR" "$SHORT" "$(stamp 90)" > "$LAB/nm/$SCEN/runs"
    STATUS_LINE='paused: waiting on rerun' ;;
  same-head-rerun-completed)
    run_toon failed failed "" > "$LAB/nm/$SCEN/axi"
    printf '  completed  %s %s  %s  https://github.com/o/r/pull/2\n  failed     %s %s  %s\n' "$BR" "$SHORT" "$(stamp 20)" "$BR" "$SHORT" "$(stamp 90)" > "$LAB/nm/$SCEN/runs" ;;
  genuine-current-failure-after-done-word)
    run_toon failed failed "https://github.com/o/r/pull/9" > "$LAB/nm/$SCEN/axi"
    printf '  failed     %s %s  %s  https://github.com/o/r/pull/9\n' "$BR" "$SHORT" "$(stamp 30)" > "$LAB/nm/$SCEN/runs"
    STATUS_LINE='done: PR https://github.com/o/r/pull/9' ;;
  newer-cancelled-row)
    run_toon failed failed "" > "$LAB/nm/$SCEN/axi"
    printf '  cancelled  %s %s  %s  https://github.com/o/r/pull/3\n  failed     %s %s  %s\n' "$BR" "$SHORT" "$(stamp 20)" "$BR" "$SHORT" "$(stamp 90)" > "$LAB/nm/$SCEN/runs" ;;
  failed-run-aged-out-of-ledger)
    run_toon failed failed "https://github.com/o/r/pull/9" > "$LAB/nm/$SCEN/axi"
    : > "$LAB/nm/$SCEN/runs" ;;
  socket-refusal-over-contradicted-failure)
    run_toon failed failed "" > "$LAB/nm/$SCEN/axi"
    printf '  completed  %s %s  %s  https://github.com/o/r/pull/2\n  failed     %s %s  %s\n' "$BR" "$SHORT" "$(stamp 20)" "$BR" "$SHORT" "$(stamp 90)" > "$LAB/nm/$SCEN/runs"
    STATUS_LINE='blocked: no-mistakes daemon socket connection refused' ;;
  stale-failed-newer-completed-other-head)
    run_toon failed failed "" > "$LAB/nm/$SCEN/axi"
    printf '  completed  %s f0f0f0f0  %s  https://github.com/o/r/pull/2890\n  failed     %s %s  %s\n' "$BR" "$(stamp 30)" "$BR" "$SHORT" "$(stamp 60)" > "$LAB/nm/$SCEN/runs"
    STATUS_LINE='paused: rerun shipped elsewhere' ;;
  stale-passed-newer-failed-other-head)
    run_toon completed passed "https://github.com/o/r/pull/7" > "$LAB/nm/$SCEN/axi"
    printf '  failed     %s f0f0f0f0  %s\n  completed  %s %s  %s  https://github.com/o/r/pull/7\n' "$BR" "$(stamp 30)" "$BR" "$SHORT" "$(stamp 60)" > "$LAB/nm/$SCEN/runs" ;;
  *) echo "unknown scenario $SCEN" >&2; exit 2 ;;
esac
. "$REPO/bin/fm-meta-lib.sh" 2>/dev/null || true
cat > "$LAB/state/$ID.meta" <<EOF
window=firstmate:fm-$ID
worktree=$WT
project=$WT
harness=codex
kind=ship
mode=no-mistakes
yolo=off
spawn_gen=lab.1
pr=https://github.com/o/r/pull/1
pr_head=$HEAD_SHA
EOF
printf '%s\n' "$STATUS_LINE" > "$LAB/state/$ID.status"
: > "$LAB/state/$ID.turn-ended"
old=$(date -d "@$(( $(date +%s) - 600 ))" +%Y%m%d%H%M.%S)
touch -t "$old" "$LAB/state/$ID.meta" "$LAB/state/$ID.status" "$LAB/state/$ID.turn-ended"
export FM_LAB_NM="$LAB/nm" FM_LAB_SCEN="$SCEN"
run_env() {
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
    -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u TMUX -u TMUX_PANE \
    PATH="$STUB:$PATH" TMUX_TMPDIR="$LAB/tmux" FM_HOME="$LAB" FM_INACTIVE_RECONCILE_SECS=60 "$@"
}
echo "### scenario: $SCEN   (tree: $REPO)"
echo "--- status log: $STATUS_LINE"
echo "--- meta pr=https://github.com/o/r/pull/1 (older recorded task PR)"
echo "--- stub axi status:"; sed 's/^/    /' "$LAB/nm/$SCEN/axi"
echo "--- stub runs ledger:"; sed 's/^/    /' "$LAB/nm/$SCEN/runs"
echo "--- \$ fm-crew-state.sh $ID"
run_env "$REPO/bin/fm-crew-state.sh" "$ID"
echo "--- \$ fm-inactive-reconcile.sh scan --startup"
run_env "$REPO/bin/fm-inactive-reconcile.sh" scan --startup; echo "    (exit $?)"
echo "--- wake queue inactive-outcome records:"
grep -h 'inactive-outcome' "$LAB/state/.wake-queue" 2>/dev/null | sed 's/^/    /' || echo "    (none)"
[ -s "$LAB/state/.wake-queue" ] && grep -q inactive-outcome "$LAB/state/.wake-queue" || echo "    (none queued)"
echo

#!/usr/bin/env bash
# Live scenario: a finished task's pane id is reissued, after a Herdr restart,
# to a NEW task spawned in the same home while the old record still exists.
# Drives real fm-spawn, fm-send, fm-crew-state, fm-peek and fm-teardown against
# an isolated fm-lab-* session through bin/fm-herdr-lab.sh.
set -u
ROOT=${ROOT:?}
HERDR_LAB_HELPER=$ROOT/bin/fm-herdr-lab.sh
REAL_TREEHOUSE=$(command -v treehouse)
HERDR_ORIGINAL_PATH=$PATH
TMP_ROOT=$(mktemp -d "$(cd "${TMPDIR:-/tmp}" && pwd -P)/fm-live-reuse.XXXXXX")
FAKEBIN=$TMP_ROOT/fakebin; mkdir -p "$FAKEBIN"
HERDR_LAB_SESSION=$("$HERDR_LAB_HELPER" name fm-live-reuse)
export HERDR_LAB_HELPER HERDR_LAB_SESSION HERDR_ORIGINAL_PATH HERDR_SESSION=$HERDR_LAB_SESSION
WTS=
FAILED=0
ok() { printf 'ok - %s\n' "$1"; }
bad() { printf 'not ok - %s\n' "$1"; FAILED=1; }
cleanup() {
  for wt in $WTS; do [ -d "$wt" ] && "$REAL_TREEHOUSE" return --force "$wt" >/dev/null 2>&1; done
  env PATH="$HERDR_ORIGINAL_PATH" "$HERDR_LAB_HELPER" teardown "$HERDR_LAB_SESSION" >/dev/null 2>&1 || echo "WARN: lab teardown failed"
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
cat > "$FAKEBIN/herdr" <<'SH'
#!/usr/bin/env bash
set -u
args=("$@"); last=$((${#args[@]} - 1)); flag=$((last - 1))
if [ "${#args[@]}" -ge 2 ] && [ "${args[$flag]}" = --session ] && [ "${args[$last]}" = "$HERDR_LAB_SESSION" ]; then
  unset "args[$last]" "args[$flag]"
fi
set -- "${args[@]}"
for a in "$@"; do case "$a" in --session|--session=*) exit 9 ;; esac; done
if [ "${1:-}" = --version ]; then exec env PATH="$HERDR_ORIGINAL_PATH" herdr "$@" --session "$HERDR_LAB_SESSION"; fi
exec env PATH="$HERDR_ORIGINAL_PATH" "$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" "$@"
SH
chmod +x "$FAKEBIN/herdr"
export PATH="$FAKEBIN:$PATH"
lab() { env PATH="$HERDR_ORIGINAL_PATH" "$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" "$@"; }
env PATH="$HERDR_ORIGINAL_PATH" "$HERDR_LAB_HELPER" provision "$HERDR_LAB_SESSION" || { echo "provision failed"; exit 1; }

HOME_DIR=$TMP_ROOT/home; PROJECT=$TMP_ROOT/project
mkdir -p "$HOME_DIR/state" "$HOME_DIR/config" "$HOME_DIR/data"
touch "$HOME_DIR/state/.last-watcher-beat"
mkdir -p "$PROJECT"; git -C "$PROJECT" init -q; echo x > "$PROJECT/README.md"; git -C "$PROJECT" add README.md
git -C "$PROJECT" -c user.name=t -c user.email=t@e.invalid commit -qm init
git clone -q --bare "$PROJECT" "$PROJECT.origin.git"; git -C "$PROJECT" remote add origin "file://$PROJECT.origin.git"
for id in anchor oldtask newtask; do
  mkdir -p "$HOME_DIR/data/$id"
  printf '# Task\n## Captain'"'"'s intent\nLive pane reuse fixture %s.\n\n## Firstmate spec\nNothing.\n' "$id" > "$HOME_DIR/data/$id/brief.md"
done
envh() { env FM_GATE_REFUSE_BYPASS=1 FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$HOME_DIR/state" \
  FM_DATA_OVERRIDE="$HOME_DIR/data" FM_CONFIG_OVERRIDE="$HOME_DIR/config" "$@"; }
spawn() { envh FM_SPAWN_NO_GUARD=1 "$ROOT/bin/fm-spawn.sh" "$1" "$PROJECT" "bash -c 'echo LAUNCHED-$1; exec -a claude sleep 900'" --mode no-mistakes --yolo off --backend herdr; }
mv_() { grep "^$2=" "$HOME_DIR/state/$1.meta" | cut -d= -f2-; }
run() { echo "\$ $*"; "$@"; }

echo "== 1. spawn an anchor and the task that will finish (presentation projection on by default)"
spawn anchor > "$TMP_ROOT/a.out" 2>&1 || { cat "$TMP_ROOT/a.out"; bad 'anchor spawn'; exit 1; }
WTS="$WTS $(mv_ anchor worktree)"
spawn oldtask > "$TMP_ROOT/o.out" 2>&1 || { cat "$TMP_ROOT/o.out"; bad 'oldtask spawn'; exit 1; }
WTS="$WTS $(mv_ oldtask worktree)"
echo "--- state/oldtask.meta (endpoint lines)"; grep -E '^(window|backend|herdr_)' "$HOME_DIR/state/oldtask.meta"
OLD_WIN=$(mv_ oldtask window); OLD_PANE=$(mv_ oldtask herdr_pane_id); OLD_WS=$(mv_ oldtask herdr_workspace_id); OLD_TERM=$(mv_ oldtask herdr_terminal_id)
LIVE_TERM=$(lab pane get "$OLD_PANE" | jq -r '.result.pane.terminal_id')
[ -n "$OLD_TERM" ] && [ "$OLD_TERM" = "$LIVE_TERM" ] && ok "spawned record binds live terminal id $OLD_TERM for pane $OLD_PANE" || bad "record terminal '$OLD_TERM' vs live '$LIVE_TERM'"
envh "$ROOT/bin/fm-crew-state.sh" oldtask 2>&1 | sed 's/^/crew-state oldtask (live): /'

echo "== 2. the worker finishes: its projected workspace $OLD_WS closes; record stays. Then the Herdr server restarts."
if [ "$OLD_WS" = "$(mv_ anchor herdr_workspace_id)" ]; then echo "NOTE: old task shares the anchor workspace; closing its tab"; lab tab close "$(mv_ oldtask herdr_tab_id)" >/dev/null; else lab workspace close "$OLD_WS" >/dev/null; fi
env PATH="$HERDR_ORIGINAL_PATH" "$HERDR_LAB_HELPER" stop "$HERDR_LAB_SESSION" >/dev/null || bad 'stop'
env PATH="$HERDR_ORIGINAL_PATH" "$HERDR_LAB_HELPER" provision "$HERDR_LAB_SESSION" >/dev/null || bad 'reprovision'
# The restart ended the anchor's agent; its record no longer owns a live slot (as in the presentation e2e).
rm -f "$HOME_DIR/state/anchor.meta"

echo "== 3. spawn a new task in the same home while the old record still exists"
spawn newtask > "$TMP_ROOT/n.out" 2>&1 || { cat "$TMP_ROOT/n.out"; bad 'newtask spawn after restart failed'; }
WTS="$WTS $(mv_ newtask worktree)"
echo "--- state/newtask.meta (endpoint lines)"; grep -E '^(window|backend|herdr_)' "$HOME_DIR/state/newtask.meta"
NEW_WIN=$(mv_ newtask window); NEW_PANE=$(mv_ newtask herdr_pane_id); NEW_TERM=$(mv_ newtask herdr_terminal_id)
if [ "$NEW_WIN" = "$OLD_WIN" ]; then ok "repro: Herdr reissued pane $OLD_PANE to the new task; two records now name $NEW_WIN ($OLD_TERM vs $NEW_TERM)"; REISSUED=1
else echo "NOTE: new task got $NEW_WIN, not reissued $OLD_WIN; driving the stranger path with a lab pane"; REISSUED=0; fi
sleep 2
lab pane report-agent --source fm-live-reuse --agent claude --state idle "$NEW_PANE" >/dev/null || bad 'report-agent'
if lab pane read "$NEW_PANE" --source recent --lines 50 2>/dev/null | grep -q "LAUNCHED-newtask"; then ok "the new task's launch command was typed and ran in its pane"; else bad "new task launch output not seen"; lab pane read "$NEW_PANE" --source recent --lines 50; fi

echo "== 4. per-task reads bind each task's own record"
CS_OLD=$(envh FM_CREW_STATE_NO_FORGE=1 "$ROOT/bin/fm-crew-state.sh" oldtask 2>&1); echo "crew-state oldtask: $CS_OLD"
CS_NEW=$(envh FM_CREW_STATE_NO_FORGE=1 "$ROOT/bin/fm-crew-state.sh" newtask 2>&1); echo "crew-state newtask: $CS_NEW"
echo "$CS_NEW" | grep -q 'source: pane' && ok "crew-state reads the new task from its live pane" || bad "crew-state newtask not pane-sourced"
echo "$CS_OLD" | grep -q 'source: pane' && bad "crew-state reads the finished task from the reissued pane" || ok "crew-state does not read the finished task from the reissued pane"
P_OLD=$(envh "$ROOT/bin/fm-peek.sh" oldtask 20 2>&1); rc=$?; echo "fm-peek oldtask rc=$rc: $(printf '%s' "$P_OLD" | tail -3)"
printf '%s' "$P_OLD" | grep -q LAUNCHED-newtask && bad "fm-peek oldtask showed the new task's pane" || ok "fm-peek oldtask does not show the new task's pane"
P_NEW=$(envh "$ROOT/bin/fm-peek.sh" newtask 20 2>&1); printf '%s' "$P_NEW" | grep -q LAUNCHED-newtask && ok "fm-peek newtask shows its own pane" || { bad "fm-peek newtask"; echo "$P_NEW" | tail -5; }
envh "$ROOT/bin/fm-send.sh" oldtask "STEER-FOR-OLD" > "$TMP_ROOT/so" 2>&1; echo "fm-send oldtask rc=$?: $(tail -2 "$TMP_ROOT/so")"
envh "$ROOT/bin/fm-send.sh" newtask "STEER-FOR-NEW" > "$TMP_ROOT/sn" 2>&1; echo "fm-send newtask rc=$?: $(tail -2 "$TMP_ROOT/sn")"
sleep 1
SCREEN=$(lab pane read "$NEW_PANE" --source recent --lines 80 2>/dev/null)
echo "--- new task pane screen (tail)"; printf '%s\n' "$SCREEN" | tail -8
printf '%s' "$SCREEN" | grep -q 'oldtask' && bad "old task's doorbell reached the new task's pane" || ok "old task's doorbell did not reach the new task's pane"
printf '%s' "$SCREEN" | grep -q 'newtask' && ok "the new task's own doorbell reached its pane" || echo "NOTE: new task doorbell not visible on screen"

echo "== 5. tear down the finished task: nothing of the new task's may be closed"
envh "$ROOT/bin/fm-teardown.sh" oldtask --force > "$TMP_ROOT/to" 2>&1; rc=$?; echo "fm-teardown oldtask rc=$rc"; sed 's/^/  /' "$TMP_ROOT/to" | tail -12
lab pane get "$NEW_PANE" >/dev/null 2>&1 && ok "the new task's pane $NEW_PANE survived teardown of the finished task" || bad "teardown of the finished task closed the new task's pane"
[ ! -e "$HOME_DIR/state/oldtask.meta" ] && [ "$rc" = 0 ] && ok "the finished task's record was cleaned up" || bad "old record remained / teardown rc=$rc"
grep -q 'belongs to another terminal' "$TMP_ROOT/to" && ok "teardown reported the pane now belongs to another terminal"
CS_NEW2=$(envh FM_CREW_STATE_NO_FORGE=1 "$ROOT/bin/fm-crew-state.sh" newtask 2>&1); echo "crew-state newtask after: $CS_NEW2"

echo "== 6. tear down the new task: it closes its own pane"
envh "$ROOT/bin/fm-teardown.sh" newtask --force > "$TMP_ROOT/tn" 2>&1; rc=$?; echo "fm-teardown newtask rc=$rc"; tail -4 "$TMP_ROOT/tn" | sed 's/^/  /'
lab pane get "$NEW_PANE" >/dev/null 2>&1 && bad "teardown of the new task left its pane" || ok "teardown of the new task closed its own pane"
echo "RESULT failed=$FAILED"
exit $FAILED

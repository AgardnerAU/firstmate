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

echo "== spawn a task, the worker finishes, its workspace closes, and its record's window is cleared"
spawn anchor > "$TMP_ROOT/a.out" 2>&1 || { cat "$TMP_ROOT/a.out"; exit 1; }
WTS="$WTS $(mv_ anchor worktree)"
spawn oldtask > "$TMP_ROOT/o.out" 2>&1 || { cat "$TMP_ROOT/o.out"; exit 1; }
WTS="$WTS $(mv_ oldtask worktree)"
lab workspace close "$(mv_ oldtask herdr_workspace_id)" >/dev/null
BEFORE=$(lab pane list 2>/dev/null | jq -c '[.result.panes[]?.pane_id]')
sed -i '' '/^window=/d' "$HOME_DIR/state/oldtask.meta"
echo "--- state/oldtask.meta endpoint lines after clearing window"; grep -E '^(window|backend|endpoint_task_id|herdr_)' "$HOME_DIR/state/oldtask.meta"
envh "$ROOT/bin/fm-teardown.sh" oldtask --force > "$TMP_ROOT/t" 2>&1; rc=$?
echo "fm-teardown oldtask rc=$rc"; sed 's/^/  /' "$TMP_ROOT/t" | grep -v '^  /' | tail -6
AFTER=$(lab pane list 2>/dev/null | jq -c '[.result.panes[]?.pane_id]')
[ "$rc" = 0 ] && [ ! -e "$HOME_DIR/state/oldtask.meta" ] && ok "a windowless finished Herdr record is accepted by cleanup" || bad "windowless Herdr record refused (rc=$rc)"
[ "$BEFORE" = "$AFTER" ] && ok "no Herdr pane was closed ($AFTER)" || bad "panes changed: $BEFORE -> $AFTER"
envh "$ROOT/bin/fm-teardown.sh" anchor --force >/dev/null 2>&1 || true
echo "RESULT failed=$FAILED"; exit $FAILED

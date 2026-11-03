#!/usr/bin/env bash
# Live driver: real fm-spawn / fm-teardown against a named fm-lab-* Herdr
# session (only through bin/fm-herdr-lab.sh) and a real Treehouse pool rooted
# in a throwaway directory.
# Usage: live-lease-driver.sh <firstmate-root> <mode: full|restart-only>
set -u
ROOT=$1
MODE=${2:-full}
HELPER="$ROOT/bin/fm-herdr-lab.sh"
step() { printf '\n=== %s\n' "$*"; }
ok() { printf 'PASS: %s\n' "$*"; }
bad() { printf 'FAIL: %s\n' "$*"; FAILED=1; }
FAILED=0

REAL_HERDR=$(command -v herdr); REAL_TREEHOUSE=$(command -v treehouse)
HERDR_ORIGINAL_PATH=$PATH
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-lease-live.XXXXXX")
FAKEBIN="$TMP_ROOT/fakebin"; mkdir -p "$FAKEBIN"
export TREEHOUSE_ROOT="$TMP_ROOT/pool"
TH_LOG="$TMP_ROOT/treehouse.log"; : > "$TH_LOG"
export REAL_HERDR REAL_TREEHOUSE HERDR_ORIGINAL_PATH HELPER TH_LOG

unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION
HERDR_LAB_SESSION=$("$HELPER" name lease-live)
export HERDR_LAB_SESSION HERDR_SESSION="$HERDR_LAB_SESSION"
LAB_READY=0
cleanup() {
  hl viewer stop "$HERDR_LAB_SESSION" >/dev/null 2>&1 || true
  [ "$LAB_READY" = 1 ] && hl teardown "$HERDR_LAB_SESSION" >/dev/null 2>&1
  find "$TMP_ROOT" -type d -exec chmod u+rwx {} + 2>/dev/null || true
  rm -rf "$TMP_ROOT"
  echo "cleanup: lab $HERDR_LAB_SESSION torn down, $TMP_ROOT removed"
}
trap cleanup EXIT

# herdr wrapper: strip the adapter's trailing lab --session, route via helper.
cat > "$FAKEBIN/herdr" <<'SH'
#!/usr/bin/env bash
args=("$@"); n=${#args[@]}
if [ "$n" -ge 2 ] && [ "${args[n-2]}" = --session ] && [ "${args[n-1]}" = "$HERDR_LAB_SESSION" ]; then
  unset "args[n-1]" "args[n-2]"
fi
set -- "${args[@]}"
if [ "${1:-}" = --version ]; then
  exec env PATH="$HERDR_ORIGINAL_PATH" "$REAL_HERDR" "$@" --session "$HERDR_LAB_SESSION"
fi
exec env PATH="$HERDR_ORIGINAL_PATH" "$HELPER" run "$HERDR_LAB_SESSION" "$@"
SH
# treehouse wrapper: on return, record whether the task pane still exists.
cat > "$FAKEBIN/treehouse" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = return ] && [ -f "$TH_PROBE_PANE_FILE" ]; then
  pane=$(cat "$TH_PROBE_PANE_FILE")
  if env PATH="$HERDR_ORIGINAL_PATH" "$HELPER" run "$HERDR_LAB_SESSION" pane get "$pane" >/dev/null 2>&1; then
    state=PANE-STILL-PRESENT
  else
    state=pane-gone
  fi
  printf 'treehouse %s  [task pane %s: %s at return]\n' "$*" "$pane" "$state" >> "$TH_LOG"
else
  printf 'treehouse %s\n' "$*" >> "$TH_LOG"
fi
exec "$REAL_TREEHOUSE" "$@"
SH
chmod +x "$FAKEBIN/herdr" "$FAKEBIN/treehouse"
export TH_PROBE_PANE_FILE="$TMP_ROOT/probe-pane"
export PATH="$FAKEBIN:$PATH"
hl() { env PATH="$HERDR_ORIGINAL_PATH" "$HELPER" "$@"; }
lab() { env PATH="$HERDR_ORIGINAL_PATH" "$HELPER" run "$HERDR_LAB_SESSION" "$@"; }

hl provision "$HERDR_LAB_SESSION" || { echo "provision failed"; exit 1; }
LAB_READY=1
echo "lab session: $HERDR_LAB_SESSION  herdr: $("$REAL_HERDR" --version)  root: $ROOT ($(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo archive))"

HOME_DIR="$TMP_ROOT/home"; PROJ="$TMP_ROOT/project"
mkdir -p "$HOME_DIR/state" "$HOME_DIR/config"; touch "$HOME_DIR/state/.last-watcher-beat"
mkdir -p "$PROJ"; git -C "$PROJ" init -q; echo '# fixture' > "$PROJ/README.md"
git -C "$PROJ" add README.md; git -C "$PROJ" -c user.name=t -c user.email=t@example.invalid commit -qm init
git clone -q --bare "$PROJ" "$PROJ.origin.git"; git -C "$PROJ" remote add origin "file://$PROJ.origin.git"
brief() { mkdir -p "$HOME_DIR/data/$1"; printf '# Task\n## Captain'"'"'s intent\nLive lease fixture %s.\n\n## Firstmate spec\nNone.\n' "$1" > "$HOME_DIR/data/$1/brief.md"; }
spawn() { FM_GATE_REFUSE_BYPASS=1 FM_SPAWN_NO_GUARD=1 FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$ROOT" \
  "$ROOT/bin/fm-spawn.sh" "$1" "$PROJ" "sh -c 'while :; do sleep 60; done'" --mode no-mistakes --yolo off --backend herdr; }
teardown() { FM_GATE_REFUSE_BYPASS=1 FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$HOME_DIR/state" \
  FM_DATA_OVERRIDE="$HOME_DIR/data" FM_CONFIG_OVERRIDE="$HOME_DIR/config" "$ROOT/bin/fm-teardown.sh" "$1" --force; }
meta() { grep "^$2=" "$HOME_DIR/state/$1.meta" | cut -d= -f2-; }
pane_cwd() { lab pane get "$1" | jq -r '.result.pane.cwd // empty'; }
pool_status() { (cd "$PROJ" && "$REAL_TREEHOUSE" status 2>&1); }

step "Scenario A: fresh Herdr spawn leases the task copy and moves the pane's top-level shell there"
brief lease-a
spawn lease-a > "$TMP_ROOT/a.out" 2>&1 || { cat "$TMP_ROOT/a.out"; bad "spawn lease-a failed"; exit 1; }
WT_A=$(meta lease-a worktree); PANE_A=$(meta lease-a herdr_pane_id)
echo "meta worktree=$WT_A  pane=$PANE_A"
echo "treehouse calls during spawn:"; sed 's/^/  /' "$TH_LOG"
echo "pool status:"; pool_status | sed 's/^/  /'
CWD_A=$(pane_cwd "$PANE_A"); echo "herdr pane get .cwd = $CWD_A"
lab pane get "$PANE_A" | jq -c '.result.pane | {pane_id, cwd, foreground_cwd}'
[ -n "$WT_A" ] && [ "$CWD_A" = "$WT_A" ] && ok "pane top-level cwd equals leased copy" || bad "pane cwd ($CWD_A) != task copy ($WT_A)"

step "Scenario B: full Herdr session restart (lab stop + provision) restores the pane"
hl stop "$HERDR_LAB_SESSION" >/dev/null || bad "lab stop failed"
hl provision "$HERDR_LAB_SESSION" >/dev/null || { bad "lab re-provision failed"; exit 1; }
sleep 2
if lab pane get "$PANE_A" >/dev/null 2>&1; then
  lab pane get "$PANE_A" | jq -c '.result.pane | {pane_id, cwd, foreground_cwd}'
  RCWD=$(pane_cwd "$PANE_A"); echo "restored pane cwd = $RCWD (project clone = $PROJ)"
  [ "$RCWD" = "$WT_A" ] && ok "restored worker pane is in its own task copy, not the project clone" \
    || bad "restored pane opened in $RCWD instead of $WT_A"
else
  bad "restored pane $PANE_A not present after restart"
fi
[ "$MODE" = restart-only ] && { teardown lease-a > "$TMP_ROOT/ta.out" 2>&1; exit "$FAILED"; }

step "Scenario C: teardown of a viewed task tab is refused and retains task, pane shell and leased copy"
brief lease-c
: > "$TH_LOG"
spawn lease-c > "$TMP_ROOT/c.out" 2>&1 || { cat "$TMP_ROOT/c.out"; bad "spawn lease-c failed"; exit 1; }
WT_C=$(meta lease-c worktree); PANE_C=$(meta lease-c herdr_pane_id); TAB_C=$(meta lease-c herdr_tab_id)
printf '%s' "$PANE_C" > "$TH_PROBE_PANE_FILE"
echo "lease-c worktree=$WT_C pane=$PANE_C tab=$TAB_C"
hl viewer start "$HERDR_LAB_SESSION" >/dev/null || bad "viewer start failed"
lab tab focus "$TAB_C" >/dev/null || bad "tab focus failed"
lab workspace list | jq -c '[.result.workspaces[] | {workspace_id, label, focused, active_tab_id}]'
: > "$TH_LOG"
rc=0; teardown lease-c > "$TMP_ROOT/c-td1.out" 2>&1 || rc=$?
echo "teardown rc=$rc; output:"; sed 's/^/  /' "$TMP_ROOT/c-td1.out"
echo "treehouse calls during refused teardown:"; sed 's/^/  /' "$TH_LOG"
[ "$rc" -ne 0 ] && ok "teardown exited non-zero" || bad "teardown succeeded despite viewed tab"
grep -q "not confirmed gone" "$TMP_ROOT/c-td1.out" && ok "teardown explains it retained the task" || bad "no 'not confirmed gone' message"
lab pane get "$PANE_C" >/dev/null 2>&1 && ok "task pane $PANE_C still alive (shell not reaped)" || bad "task pane vanished"
[ -d "$WT_C" ] && ok "task copy directory still present" || bad "task copy removed"
grep -q '^treehouse return' "$TH_LOG" && bad "treehouse return was called" || ok "no treehouse return call"
[ -f "$HOME_DIR/state/lease-c.meta" ] && ok "task meta retained" || bad "task meta removed"
echo "pool status:"; pool_status | sed 's/^/  /'

step "Scenario D: retry after the captain leaves the tab closes the exact pane before returning the copy"
hl viewer stop "$HERDR_LAB_SESSION" >/dev/null || bad "viewer stop failed"
: > "$TH_LOG"
rc=0; teardown lease-c > "$TMP_ROOT/c-td2.out" 2>&1 || rc=$?
echo "teardown rc=$rc; output:"; sed 's/^/  /' "$TMP_ROOT/c-td2.out"
echo "treehouse calls:"; sed 's/^/  /' "$TH_LOG"
[ "$rc" -eq 0 ] && ok "retry teardown succeeded" || bad "retry teardown failed"
lab pane get "$PANE_C" >/dev/null 2>&1 && bad "pane still alive" || ok "exact pane gone"
grep -q 'return.*pane-gone at return' "$TH_LOG" && ! grep -q PANE-STILL-PRESENT "$TH_LOG" \
  && ok "treehouse return ran only after the pane was gone" || bad "return ordering not proven"
[ ! -f "$HOME_DIR/state/lease-c.meta" ] && ok "task record retired" || bad "meta remains"
echo "pool status:"; pool_status | sed 's/^/  /'

step "Scenario E: teardown of the restart-restored task closes its pane before returning its copy"
printf '%s' "$PANE_A" > "$TH_PROBE_PANE_FILE"; : > "$TH_LOG"
rc=0; teardown lease-a > "$TMP_ROOT/a-td.out" 2>&1 || rc=$?
echo "teardown rc=$rc; output:"; sed 's/^/  /' "$TMP_ROOT/a-td.out"
echo "treehouse calls:"; sed 's/^/  /' "$TH_LOG"
[ "$rc" -eq 0 ] && ok "teardown succeeded" || bad "teardown failed"
grep -q 'return.*pane-gone at return' "$TH_LOG" && ! grep -q PANE-STILL-PRESENT "$TH_LOG" \
  && ok "copy returned after pane gone" || bad "return ordering not proven"
echo "pool status:"; pool_status | sed 's/^/  /'
echo; [ "$FAILED" = 0 ] && echo "ALL SCENARIOS PASSED" || echo "SOME SCENARIOS FAILED"
exit "$FAILED"

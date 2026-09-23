#!/usr/bin/env bash
# Live drive: real bin/fm-teardown.sh against a real Herdr lab session in which
# a finished task's pane id has been reissued to an unrelated "claude" agent.
# Usage: live-teardown-reissued-pane.sh <repo-root> [base-root]
# <base-root>, when given, is an extracted tree of the base commit; its teardown
# is driven last on the same shape to reproduce the original defect.
set -u
ROOT=$1
BASE_ROOT=${2:-}
. "$ROOT/tests/lib.sh"
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane

HELPER="$ROOT/bin/fm-herdr-lab.sh"
ORIG_PATH=$PATH
TMP_ROOT=$(fm_test_tmproot fm-live-teardown-reuse)
LAB=$("$HELPER" name live-td-reuse)
export HELPER LAB ORIG_PATH
cleanup() {
  local s=$?
  env PATH="$ORIG_PATH" "$HELPER" teardown "$LAB" || s=1
  fm_test_cleanup
  exit "$s"
}
trap cleanup EXIT
"$HELPER" provision "$LAB" || exit 1
echo "lab session: $LAB"
lab() { env PATH="$ORIG_PATH" "$HELPER" run "$LAB" "$@"; }

make_case() { # <name>
  local c="$TMP_ROOT/$1" fb
  fb="$c/fakebin"
  mkdir -p "$c/state" "$c/config" "$c/data" "$fb"
  for t in treehouse tmux gh no-mistakes; do printf '#!/usr/bin/env bash\nexit 0\n' > "$fb/$t"; done
  cat > "$fb/gh-axi" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "pr list") printf '%s\n' "count: 0 (showing first 0)" "pull_requests[]: []"; exit 0 ;;
  "pr view") echo "error: pull request not found" >&2; exit 1 ;;
esac
exit 0
SH
  # Real herdr, routed through the lab helper, with every call logged.
  cat > "$fb/herdr" <<SH
#!/usr/bin/env bash
set -u
printf '%s\n' "\$*" >> "$c/herdr.log"
args=("\$@"); last=\$((\${#args[@]} - 1)); flag=\$((last - 1))
if [ "\${#args[@]}" -ge 2 ] && [ "\${args[\$flag]}" = --session ] && [ "\${args[\$last]}" = "\$LAB" ]; then
  unset "args[\$last]" "args[\$flag]"
fi
set -- "\${args[@]}"
for a in "\$@"; do case "\$a" in --session|--session=*) exit 9 ;; esac; done
exec env PATH="\$ORIG_PATH" "\$HELPER" run "\$LAB" "\$@"
SH
  chmod +x "$fb"/*
  git init -q --bare "$c/origin.git"
  git -C "$c/origin.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$c/origin.git" "$c/_seed" 2>/dev/null
  git -C "$c/_seed" -c user.email=t@t -c user.name=t commit -q --allow-empty -m baseline
  git -C "$c/_seed" push -q origin main
  rm -rf "$c/_seed"
  git clone -q "$c/origin.git" "$c/project"
  git -C "$c/project" remote set-head origin main 2>/dev/null || true
  git -C "$c/project" worktree add -q -b fm/task-x1 "$c/wt" main
  touch "$c/state/.last-watcher-beat"
  # No backlog: this host's tasks-axi (0.2.5) predates the 0.2.6 features the
  # automatic backlog transition needs, so the transition is left out.
  printf '%s\n' "$c"
}

run_teardown() { # <case> <teardown-root>
  local c=$1 r=$2
  FM_ROOT_OVERRIDE="$r" FM_STATE_OVERRIDE="$c/state" FM_DATA_OVERRIDE="$c/data" \
  FM_CONFIG_OVERRIDE="$c/config" PATH="$c/fakebin:$ORIG_PATH" \
    "$r/bin/fm-teardown.sh" task-x1
}

stranger_alive() { # <pane>
  lab pane process-info --pane "$1" 2>/dev/null \
    | jq -e '.result.process_info.foreground_processes[]? | select(.argv0 == "claude")' >/dev/null 2>&1
}

# --- a finished task's endpoint -------------------------------------------------
CASE=$(make_case bound)
lab workspace create --cwd "$CASE/project" --label home --no-focus >/dev/null || fail 'home workspace'
WS=$(lab workspace create --cwd "$CASE/wt" --label task --no-focus | jq -er '.result.workspace.workspace_id') || fail 'task workspace'
TAB=$(lab tab create --workspace "$WS" --cwd "$CASE/wt" --label fm-task-x1 --no-focus) || fail 'task tab'
PANE=$(printf '%s' "$TAB" | jq -er '.result.root_pane.pane_id')
TAB_ID=$(printf '%s' "$TAB" | jq -er '.result.root_pane.tab_id')
TERM_OLD=$(printf '%s' "$TAB" | jq -er '.result.root_pane.terminal_id')
echo "finished task pane: $PANE terminal: $TERM_OLD"
write_meta() { # <case> [terminal-id] [windowless]
  local c=$1 term=${2:-} windowless=${3:-}
  {
    [ -n "$windowless" ] || printf 'window=%s:%s\n' "$LAB" "$PANE"
    printf 'endpoint_task_id=task-x1\nworktree=%s\nproject=%s\n' "$c/wt" "$c/project"
    printf 'kind=ship\nmode=no-mistakes\nharness=claude\nspawn_gen=s1790000000.1.abc\nbackend=herdr\n'
    printf 'herdr_session=%s\nherdr_workspace_id=%s\nherdr_tab_id=%s\nherdr_pane_id=%s\n' "$LAB" "$WS" "$TAB_ID" "$PANE"
    [ -z "$term" ] || printf 'herdr_terminal_id=%s\n' "$term"
  } > "$c/state/task-x1.meta"
}
write_meta "$CASE" "$TERM_OLD"
lab workspace close "$WS" >/dev/null || fail 'close finished workspace'

# --- restart; Herdr reissues the ids to an unrelated agent -----------------------
env PATH="$ORIG_PATH" "$HELPER" stop "$LAB" >/dev/null || fail 'lab stop'
env PATH="$ORIG_PATH" bash -c '. "$1/bin/fm-backend.sh"; fm_backend_source herdr && fm_backend_herdr_server_ensure "$2"' _ "$ROOT" "$LAB" \
  || fail 'lab restart'
WS2=$(lab workspace create --cwd /tmp --label firstmate --no-focus | jq -er '.result.workspace.workspace_id')
TAB2=$(lab tab create --workspace "$WS2" --cwd /tmp --label firstmate --no-focus)
PANE2=$(printf '%s' "$TAB2" | jq -er '.result.root_pane.pane_id')
TERM_NEW=$(printf '%s' "$TAB2" | jq -er '.result.root_pane.terminal_id')
echo "after restart: new workspace $WS2 pane $PANE2 terminal $TERM_NEW"
[ "$PANE2" = "$PANE" ] || fail "Herdr did not reissue $PANE (got $PANE2)"
lab pane run "$PANE" "bash -c 'exec -a claude sleep 600'" >/dev/null
for _ in $(seq 1 50); do stranger_alive "$PANE" && break; sleep 0.1; done
lab pane report-agent --source live-td --agent claude --state idle "$PANE" >/dev/null
stranger_alive "$PANE" || fail 'stranger agent did not start'
pass "repro: pane $PANE now hosts an unrelated claude agent on terminal $TERM_NEW"

# --- S1: teardown of the terminal-bound finished record --------------------------
echo "--- fm-teardown.sh task-x1 (terminal-bound record, head) ---"
OUT=$(run_teardown "$CASE" "$ROOT" 2>&1); RC=$?
printf '%s\n' "$OUT"
[ "$RC" = 0 ] || fail "teardown failed rc=$RC"
printf '%s\n' "$OUT" | grep -Fq 'now belongs to another terminal' || fail 'no reissue note'
[ ! -e "$CASE/state/task-x1.meta" ] || fail 'record left behind'
grep -E '^(pane|tab|workspace) close' "$CASE/herdr.log" && fail 'teardown issued a Herdr close'
stranger_alive "$PANE" || fail "teardown closed or disturbed the stranger's pane"
echo "herdr calls made by teardown:"; sed 's/^/  /' "$CASE/herdr.log"
pass 'head teardown retired the finished task, issued no close, and the stranger agent still runs'

# --- S2: teardown of a legacy (no terminal id) record, worktree gone -------------
CASE_L=$(make_case legacy)
write_meta "$CASE_L" ""
echo "--- fm-teardown.sh task-x1 (legacy record, head) ---"
OUT=$(run_teardown "$CASE_L" "$ROOT" 2>&1); RC=$?
printf '%s\n' "$OUT"
[ "$RC" = 0 ] || fail "legacy teardown failed rc=$RC"
grep -E '^(pane|tab|workspace) close' "$CASE_L/herdr.log" && fail 'legacy teardown issued a Herdr close'
stranger_alive "$PANE" || fail 'legacy teardown closed the stranger pane'
pass 'head teardown of a legacy record whose pane now works outside its worktree leaves the stranger alone'

# --- S3: windowless finished Herdr record ----------------------------------------
CASE_W=$(make_case windowless)
write_meta "$CASE_W" "$TERM_OLD" windowless
echo "--- fm-teardown.sh task-x1 (windowless Herdr record, head) ---"
OUT=$(run_teardown "$CASE_W" "$ROOT" 2>&1); RC=$?
printf '%s\n' "$OUT"
[ "$RC" = 0 ] || fail "windowless teardown refused rc=$RC"
[ ! -e "$CASE_W/state/task-x1.meta" ] || fail 'windowless record left behind'
[ ! -s "$CASE_W/herdr.log" ] || fail "windowless teardown called Herdr: $(cat "$CASE_W/herdr.log")"
stranger_alive "$PANE" || fail 'windowless teardown touched the stranger pane'
pass 'head teardown accepts a windowless finished Herdr record with no Herdr call'

# --- S4 (repro): the base commit's teardown on the same terminal-bound record ----
if [ -n "$BASE_ROOT" ]; then
  CASE_B=$(make_case base)
  write_meta "$CASE_B" "$TERM_OLD"
  echo "--- fm-teardown.sh task-x1 (terminal-bound record, BASE commit) ---"
  OUT=$(run_teardown "$CASE_B" "$BASE_ROOT" 2>&1); RC=$?
  printf '%s\n' "$OUT"
  echo "base rc=$RC; herdr close calls:"; grep -E '^(pane|tab|workspace) close' "$CASE_B/herdr.log" | sed 's/^/  /'
  if stranger_alive "$PANE"; then
    echo "base: stranger still alive"
  else
    echo "REPRO: the base teardown closed the unrelated agent's pane $PANE"
  fi
  CASE_BW=$(make_case base-windowless)
  write_meta "$CASE_BW" "$TERM_OLD" windowless
  echo "--- fm-teardown.sh task-x1 (windowless Herdr record, BASE commit) ---"
  OUT=$(run_teardown "$CASE_BW" "$BASE_ROOT" 2>&1); RC=$?
  printf '%s\n' "$OUT" | tail -5
  echo "base windowless rc=$RC"
fi

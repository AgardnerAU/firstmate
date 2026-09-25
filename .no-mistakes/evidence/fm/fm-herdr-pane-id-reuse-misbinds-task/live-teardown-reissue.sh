#!/usr/bin/env bash
# Live check: the real bin/fm-teardown.sh against a real Herdr lab session.
# A: a record whose pane id Herdr reissued to a stranger (terminal-bound):
#    unlanded work refuses, landed work tears down, stranger pane survives.
# B: a record that owns its live pane (match) tears down and closes that pane.
# C: a finished Herdr record with its window cleared tears down with no Herdr call.
set -u
ROOT=${ROOT:?}
HELPER="$ROOT/bin/fm-herdr-lab.sh"
ORIG_PATH=$PATH
TMP=$(mktemp -d "$(cd "${TMPDIR:-/tmp}" && pwd -P)/fm-live-td.XXXXXX")
LAB=$("$HELPER" name live-teardown)
export HERDR_LAB_SESSION=$LAB HERDR_LAB_HELPER=$HELPER HERDR_ORIGINAL_PATH=$ORIG_PATH
cleanup() { "$HELPER" teardown "$LAB" >/dev/null 2>&1 || echo "WARN teardown of $LAB failed"; rm -rf "$TMP"; }
trap cleanup EXIT
fail() { echo "FAIL - $*"; exit 1; }
ok() { echo "PASS - $*"; }
lab() { env PATH="$ORIG_PATH" "$HELPER" run "$LAB" "$@"; }
"$HELPER" provision "$LAB" >/dev/null || fail "provision"
echo "lab session: $LAB"

mkcase() { # <name>
  local c="$TMP/$1"; mkdir -p "$c/fakebin"
  "$ROOT/bin/fm-lab-home.sh" create "$c/home" >/dev/null || fail "lab home"
  for t in treehouse tmux; do printf '#!/usr/bin/env bash\nexit 0\n' > "$c/fakebin/$t"; done
  printf '#!/usr/bin/env bash\ncase "$1 $2" in "pr list") printf "%%s\\n" "count: 0 (showing first 0)" "pull_requests[]: []";; "pr view") exit 1;; esac\nexit 0\n' > "$c/fakebin/gh-axi"
  printf '#!/usr/bin/env bash\ncase "$1 $2" in "pr view") exit 1;; esac\nexit 0\n' > "$c/fakebin/gh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$c/fakebin/no-mistakes"
  # herdr routes every call through the lab helper and logs it.
  cat > "$c/fakebin/herdr" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$c/herdr.log"
args=("\$@"); n=\${#args[@]}
if [ \$n -ge 2 ] && [ "\${args[\$((n-2))]}" = --session ]; then unset "args[\$((n-1))]" "args[\$((n-2))]"; fi
exec env PATH="$ORIG_PATH" "$HELPER" run "$LAB" "\${args[@]}"
SH
  chmod +x "$c/fakebin/"*
  git init -q --bare "$c/origin.git"; git -C "$c/origin.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$c/origin.git" "$c/_s" 2>/dev/null
  git -C "$c/_s" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git -C "$c/_s" push -q origin main; rm -rf "$c/_s"
  git clone -q "$c/origin.git" "$c/project"; git -C "$c/project" remote set-head origin main 2>/dev/null
  git -C "$c/project" worktree add -q -b fm/task-x1 "$c/wt" main
  touch "$c/home/state/.last-watcher-beat"
  printf '%s\n' '# Backlog' '' '## In flight' '' '## Queued' '' '## Done' > "$c/home/data/backlog.md"
  tasks-axi add task-x1 "live fixture" --kind ship --file "$c/home/data/backlog.md" >/dev/null
  tasks-axi start task-x1 --file "$c/home/data/backlog.md" >/dev/null
  printf '%s\n' "$c"
}
record() { # <case> <ws> <tab> <pane> <terminal> [nowindow]
  local c=$1
  { [ "${6:-}" = nowindow ] || echo "window=$LAB:$4"
    echo "endpoint_task_id=task-x1"; echo "worktree=$c/wt"; echo "project=$c/project"
    echo "kind=ship"; echo "mode=local-only"; echo "spawn_gen=live-td-x1"; echo "backend=herdr"
    echo "herdr_session=$LAB"; echo "herdr_workspace_id=$2"; echo "herdr_tab_id=$3"; echo "herdr_pane_id=$4"
    [ -z "$5" ] || echo "herdr_terminal_id=$5"; } > "$c/home/state/task-x1.meta"
}
teardown() { local c=$1
  env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u FM_GATE_REFUSE_BYPASS \
    FM_HOME="$c/home" PATH="$c/fakebin:$ORIG_PATH" "$ROOT/bin/fm-teardown.sh" task-x1; }
land() { local c=$1; git -C "$c/project" update-ref refs/heads/main "$(git -C "$c/wt" rev-parse HEAD)"; }
unlanded() { printf 'x\n' > "$1/wt/f.txt"; git -C "$1/wt" add f.txt; git -C "$1/wt" -c user.email=t@t -c user.name=t commit -q -m work; }
json_ids() { jq -r '.result.root_pane | "\(.workspace_id // "") \(.tab_id) \(.pane_id) \(.terminal_id)"'; }

lab workspace create --cwd "$TMP" --label home --no-focus >/dev/null || fail "home ws"

# ---- A: reissued pane ----------------------------------------------------
CA=$(mkcase reissued)
WS=$(lab workspace create --cwd "$CA/wt" --label task --no-focus | jq -r .result.workspace.workspace_id)
read -r _ TAB PANE TERM_OLD < <(lab tab create --workspace "$WS" --cwd "$CA/wt" --label fm-task-x1 --no-focus | json_ids)
record "$CA" "$WS" "$TAB" "$PANE" "$TERM_OLD"
echo "task pane $PANE terminal $TERM_OLD"
lab workspace close "$WS" >/dev/null || fail "close task ws"
env PATH="$ORIG_PATH" "$HELPER" stop "$LAB" >/dev/null || fail "stop"
env PATH="$ORIG_PATH" bash -c '. "$1/bin/fm-backend.sh"; fm_backend_source herdr && fm_backend_herdr_server_ensure "$2"' _ "$ROOT" "$LAB" || fail restart
lab workspace create --cwd "$TMP" --label stranger --no-focus >/dev/null
read -r _ _ PANE2 TERM_NEW < <(lab tab create --workspace "$WS" --cwd "$TMP" --label stranger-agent --no-focus | json_ids)
[ "$PANE2" = "$PANE" ] || fail "Herdr did not reissue $PANE (got $PANE2)"
echo "reissued pane $PANE2 to terminal $TERM_NEW"
lab pane run "$PANE" "bash -c 'exec -a claude sleep 600'" >/dev/null
lab pane report-agent --source live-td --agent claude --state idle "$PANE" >/dev/null
unlanded "$CA"
echo "--- A1 teardown with unlanded work"
teardown "$CA"; rc=$?
echo "rc=$rc"
[ $rc -ne 0 ] && [ $rc -ne 3 ] && [ -f "$CA/home/state/task-x1.meta" ] && lab pane get "$PANE" >/dev/null 2>&1 \
  || fail "A1: unlanded work behind reissued pane did not refuse cleanly"
ok "A1: unlanded work behind a reissued pane refuses; stranger pane $PANE still present"
land "$CA"
echo "--- A2 teardown with landed work"
teardown "$CA"; rc=$?
echo "rc=$rc"
[ $rc -eq 0 ] || fail "A2: teardown refused"
[ ! -f "$CA/home/state/task-x1.meta" ] || fail "A2: record left"
grep -q '^pane close' "$CA/herdr.log" && fail "A2: teardown issued pane close: $(grep close "$CA/herdr.log")"
lab pane get "$PANE" | jq -e --arg t "$TERM_NEW" '.result.pane.terminal_id == $t' >/dev/null || fail "A2: stranger pane gone"
ok "A2: landed teardown removed the record, closed nothing, stranger pane $PANE ($TERM_NEW) still alive"

# ---- B: own pane matches and is closed -----------------------------------
CB=$(mkcase own)
WSB=$(lab workspace create --cwd "$CB/wt" --label own --no-focus | jq -r .result.workspace.workspace_id)
read -r _ TABB PANEB TERMB < <(lab tab create --workspace "$WSB" --cwd "$CB/wt" --label fm-task-x1 --no-focus | json_ids)
record "$CB" "$WSB" "$TABB" "$PANEB" "$TERMB"
echo "--- B teardown of own pane $PANEB ($TERMB)"
teardown "$CB"; rc=$?
echo "rc=$rc"
[ $rc -eq 0 ] || fail "B: teardown refused"
lab pane get "$PANEB" >/dev/null 2>&1 && fail "B: own pane still present"
lab pane get "$PANE" >/dev/null 2>&1 || fail "B: stranger pane collateral"
ok "B: a record that owns its live pane still tears down and closes that pane"

# ---- C: windowless finished Herdr record ---------------------------------
CC=$(mkcase windowless)
record "$CC" "$WS" "$TAB" "$PANE" "$TERM_OLD" nowindow
echo "--- C teardown of windowless Herdr record naming reissued pane history"
teardown "$CC"; rc=$?
echo "rc=$rc"
[ $rc -eq 0 ] || fail "C: windowless Herdr record refused"
[ ! -f "$CC/home/state/task-x1.meta" ] || fail "C: record left"
[ ! -s "$CC/herdr.log" ] || fail "C: Herdr was called: $(cat "$CC/herdr.log")"
lab pane get "$PANE" >/dev/null 2>&1 || fail "C: stranger pane gone"
ok "C: a finished Herdr record with its window cleared tears down with zero Herdr calls"
echo "ALL PASS"

#!/usr/bin/env bash
# Live driver: runs the real bin/fm-teardown.sh against a disposable marked lab
# home with a real git project + bare origin and a real tmux server on a private
# socket. Only GitHub (gh/gh-axi), the pool tool (treehouse) and no-mistakes are
# replaced by logging shims so nothing reaches real services or the real pipeline.
set -u
WT=${1:?worktree}
cd "$WT"
TEARDOWN="$WT/bin/fm-teardown.sh"
BASE=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
trap 'TMUX_TMPDIR="$BASE/tmux" tmux -L default kill-server 2>/dev/null; rm -rf "$BASE"' EXIT
mkdir -p "$BASE/tmux" "$BASE/shims"
for t in gh gh-axi treehouse no-mistakes; do
  printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "%s/shim.log"\nexit 1\n' "$t" "$BASE" > "$BASE/shims/$t"
done
printf '#!/usr/bin/env bash\nprintf "no-mistakes %%s\\n" "$*" >> "%s/shim.log"\nexit 0\n' "$BASE" > "$BASE/shims/no-mistakes"
chmod +x "$BASE"/shims/*

g() { git -c user.email=t@t -c user.name=t "$@"; }

new_lab() {  # <name>  -> sets LAB PROJ ORIGIN
  LAB="$BASE/$1"; "$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
  touch "$LAB/state/.last-watcher-beat"
  ORIGIN="$LAB/origin.git"; PROJ="$LAB/project"
  git init -q --bare "$ORIGIN"; git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
  git clone -q "$ORIGIN" "$LAB/_seed" 2>/dev/null
  g -C "$LAB/_seed" commit -q --allow-empty -m baseline; git -C "$LAB/_seed" push -q origin main; rm -rf "$LAB/_seed"
  git clone -q "$ORIGIN" "$PROJ"; git -C "$PROJ" remote set-head origin main
  : > "$BASE/shim.log"
}
task_branch_with_commit() {  # <branch> <msg>
  git -C "$PROJ" worktree add -q -b "$1" "$LAB/tmpwt" main
  printf '%s\n' "$2" > "$LAB/tmpwt/work.txt"; g -C "$LAB/tmpwt" add work.txt; g -C "$LAB/tmpwt" commit -q -m "$2"
  git -C "$PROJ" worktree remove --force "$LAB/tmpwt"
}
start_window() {  # <task-id>
  TMUX_TMPDIR="$BASE/tmux" tmux has-session -t firstmate 2>/dev/null \
    || TMUX_TMPDIR="$BASE/tmux" tmux new-session -d -s firstmate -n keep "sleep 600"
  TMUX_TMPDIR="$BASE/tmux" tmux new-window -d -t firstmate -n "fm-$1" "sleep 600"
}
windows() { TMUX_TMPDIR="$BASE/tmux" tmux list-windows -t firstmate -F '#W' 2>/dev/null | tr '\n' ' '; }
meta() {  # <id> lines...
  local id=$1; shift
  { printf 'window=firstmate:fm-%s\nendpoint_task_id=%s\n' "$id" "$id"; printf '%s\n' "$@"; printf 'spawn_gen=lab-%s\n' "$id"; } > "$LAB/state/$id.meta"
}
run() {  # <id> [args]
  local id=$1; shift
  echo "\$ fm-teardown.sh $id $*"
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
      -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u TMUX -u TMUX_PANE \
      FM_HOME="$LAB" TMUX_TMPDIR="$BASE/tmux" PATH="$BASE/shims:$PATH" \
      "$TEARDOWN" "$id" "$@" > "$LAB/out" 2>&1
  RC=$?
  sed 's/^/    | /' "$LAB/out" | grep -v '^    | *$' | head -25
  echo "    exit=$RC  meta_present=$([ -e "$LAB/state/$id.meta" ] && echo yes || echo no)  tmux_windows=[$(windows)]"
  grep -E '^treehouse' "$BASE/shim.log" | sed 's/^/    shim: /' || echo "    (treehouse never invoked)"
}

echo "=== S1: record names no worktree (empty worktree=), branch pushed to a fork remote, PR still open -> retires"
new_lab s1; task_branch_with_commit fm/t1 "t1 feature"
git init -q --bare "$LAB/fork.git"; git -C "$PROJ" remote add fork "$LAB/fork.git"; git -C "$PROJ" push -q fork fm/t1; git -C "$PROJ" fetch -q fork
start_window t1; meta t1 "worktree=" "project=$PROJ" kind=ship mode=no-mistakes branch=fm/t1
run t1

echo; echo "=== S2: recorded worktree path no longer exists, branch content squash-landed on origin/main -> retires"
new_lab s2; task_branch_with_commit fm/t2 "t2 feature"
git clone -q "$ORIGIN" "$LAB/_land"; printf 't2 feature\n' > "$LAB/_land/work.txt"; g -C "$LAB/_land" add work.txt; g -C "$LAB/_land" commit -q -m "squash t2"; git -C "$LAB/_land" push -q origin HEAD:main; rm -rf "$LAB/_land"
start_window t2; meta t2 "worktree=$LAB/gone-slot/project" "project=$PROJ" kind=ship mode=no-mistakes branch=fm/t2
run t2

echo; echo "=== S3 (adversarial): no worktree line at all, branch holds unpushed unlanded commits -> REFUSES, then --force retires"
new_lab s3; task_branch_with_commit fm/t3 "t3 unlanded secret work"
start_window t3; meta t3 "project=$PROJ" kind=ship mode=no-mistakes branch=fm/t3
run t3
echo "  branch fm/t3 still in project: $(git -C "$PROJ" rev-parse --verify -q fm/t3 >/dev/null && echo yes || echo no)"
run t3 --force

echo; echo "=== S4: slot claimed by another live task; retiring task's branch unpushed -> REFUSES; once pushed -> retires records-only, live slot untouched"
new_lab s4; task_branch_with_commit fm/stale "stale task work"
mkdir -p "$LAB/pool/1"; g -C "$PROJ" commit -q --allow-empty -m pool
git -C "$PROJ" worktree add -q --detach "$LAB/pool/1/project"
printf '{"worktrees":[{"name":"1","path":"%s"}]}\n' "$LAB/pool/1/project" > "$LAB/pool/treehouse-state.json"
printf 'task=live\nhome=%s\n' "$LAB" > "$LAB/pool/1/.fm-slot-owner"
printf 'live uncommitted edit\n' > "$LAB/pool/1/project/live-work"
start_window stale; start_window live
meta stale "worktree=$LAB/pool/1/project" "project=$PROJ" kind=ship mode=no-mistakes branch=fm/stale
meta live "worktree=$LAB/pool/1/project" "project=$PROJ" kind=ship mode=no-mistakes
( cd "$LAB/pool/1/project" && exec sleep 600 ) & WORKER=$!
before=$(git -C "$LAB/pool/1/project" status --porcelain)
run stale
git init -q --bare "$LAB/fork.git"; git -C "$PROJ" remote add fork "$LAB/fork.git"; git -C "$PROJ" push -q fork fm/stale; git -C "$PROJ" fetch -q fork
echo "  (pushed fm/stale to fork remote)"
run stale
echo "  live worker alive: $(kill -0 $WORKER 2>/dev/null && echo yes || echo no)"
echo "  live copy unchanged: $([ "$(git -C "$LAB/pool/1/project" status --porcelain)" = "$before" ] && echo yes || echo no)  live-work present: $([ -f "$LAB/pool/1/project/live-work" ] && echo yes || echo no)"
echo "  slot claim: $(head -1 "$LAB/pool/1/.fm-slot-owner")  live meta present: $([ -e "$LAB/state/live.meta" ] && echo yes || echo no)"
kill $WORKER 2>/dev/null; wait $WORKER 2>/dev/null

echo; echo "=== S5: local-only project with origin remote, branch merged into LOCAL main only, no worktree -> retires without --force"
new_lab s5; task_branch_with_commit fm/t5 "t5 local merge"
git -C "$PROJ" merge -q --ff-only fm/t5
start_window t5; meta t5 "worktree=" "project=$PROJ" kind=ship mode=local-only branch=fm/t5
run t5

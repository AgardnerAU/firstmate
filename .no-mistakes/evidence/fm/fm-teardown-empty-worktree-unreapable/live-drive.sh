#!/usr/bin/env bash
# Live driver: real bin/fm-teardown.sh against a disposable lab home, a private
# tmux server (real windows), real git repos, a real pool slot and a real live
# worker process. Only GitHub (gh / gh-axi) is stubbed, and treehouse is a
# logging spy that proves no slot is returned.
set -u
WT_ROOT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$WT_ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null || exit 1
mkdir -p "$LAB/tmux" "$LAB/fakebin" "$LAB/pool/1"
LOG="$LAB/runtime.log"; : > "$LOG"
export -n TMUX; unset TMUX
T() { TMUX_TMPDIR="$LAB/tmux" tmux "$@"; }
cat > "$LAB/fakebin/treehouse" <<SH
#!/usr/bin/env bash
printf 'treehouse %s\n' "\$*" >> "$LOG"; exit 0
SH
printf '#!/usr/bin/env bash\nexit 1\n' > "$LAB/fakebin/gh-axi"
chmod +x "$LAB/fakebin/"*
fake_gh() {  # <state>
  cat > "$LAB/fakebin/gh" <<SH
#!/usr/bin/env bash
case "\${1:-} \${2:-}" in
  "pr view") printf '%s\t%s\t%s\n' $1 0000000000000000000000000000000000000000 https://github.com/example/repo/pull/3035 ; exit 0 ;;
esac
exit 1
SH
  chmod +x "$LAB/fakebin/gh"
}
g() { git -c user.name=t -c user.email=t@example.invalid "$@"; }
PROJ="$LAB/projects/demo"; mkdir -p "$PROJ"; git init -q -b main "$PROJ"
g -C "$PROJ" commit -q --allow-empty -m base
git init -q --bare "$LAB/remote.git"
git -C "$PROJ" remote add fork "$LAB/remote.git"
g -C "$PROJ" worktree add -q --detach "$LAB/pool/1/project"
printf '{"worktrees":[{"name":"1","path":"%s"}]}\n' "$LAB/pool/1/project" > "$LAB/pool/treehouse-state.json"
SLOT="$LAB/pool/1/project"
T new-session -d -s firstmate -n keep sleep 100000
run() {  # <id> [args]
  local id=$1; shift
  echo "\$ fm-teardown.sh $id $*"
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
    -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u TMUX \
    TMUX_TMPDIR="$LAB/tmux" FM_HOME="$LAB" PATH="$LAB/fakebin:$PATH" \
    "$WT_ROOT/bin/fm-teardown.sh" "$id" "$@" 2>&1
  echo "[exit $?]"
}
win() { T new-window -d -t firstmate: -n "fm-$1" sleep 100000; }
meta() { local id=$1; shift; printf '%s\n' "window=firstmate:fm-$id" "endpoint_task_id=$id" "project=$PROJ" "$@" > "$LAB/state/$id.meta"; }
branch_with_commit() {  # <branch> <msg>
  g -C "$PROJ" branch -f "$1" main
  local blob tree
  blob=$(printf '%s\n' "$2" | git -C "$PROJ" hash-object -w --stdin)
  tree=$( { git -C "$PROJ" ls-tree "$1"; printf '100644 blob %s\t%s\n' "$blob" "${1//\//-}"; } | git -C "$PROJ" mktree)
  git -C "$PROJ" update-ref "refs/heads/$1" "$(g -C "$PROJ" commit-tree -p "$1" -m "$2" "$tree")"
}
state() { echo "--- records: $(ls "$LAB/state" | grep '\.meta$' | tr '\n' ' ')"; echo "--- tmux windows: $(T list-windows -t firstmate -F '#W' | tr '\n' ' ')"; echo "--- treehouse calls: $(cat "$LOG" | tr '\n' ';')"; }

echo "===== S1: record with empty worktree=, PR merged (the 2026-09-21 PR 3035 shape)"
fake_gh MERGED; win s1; meta s1 "worktree=" kind=ship mode=no-mistakes branch=fm/s1 pr=https://github.com/example/repo/pull/3035
run s1; state

echo; echo "===== S2: recorded worktree directory no longer exists, branch pushed to a remote"
fake_gh OPEN; branch_with_commit fm/s2 "s2 work"; git -C "$PROJ" push -q fork fm/s2; git -C "$PROJ" fetch -q fork
win s2; meta s2 "worktree=$LAB/pool/9/project" kind=ship mode=no-mistakes branch=fm/s2
run s2; state

echo; echo "===== S3: slot held by another live task; retiring task's branch has UNPUSHED commits"
branch_with_commit fm/stale "stale unpushed work"
meta live "worktree=$SLOT" kind=ship mode=no-mistakes branch=fm/live; win live
printf 'task=live\nhome=%s\n' "$LAB" > "$LAB/pool/1/.fm-slot-owner"
printf 'live uncommitted edit\n' > "$SLOT/live-work"
( cd "$SLOT" && exec sleep 100000 ) & WORKER=$!
win stale; meta stale "worktree=$SLOT" kind=ship mode=no-mistakes branch=fm/stale
BEFORE=$(git -C "$SLOT" status --porcelain)
run stale; state
echo "--- live worker pid $WORKER alive: $(kill -0 $WORKER 2>/dev/null && echo yes || echo NO)"

echo; echo "===== S4: same slot case after pushing the retiring task's branch"
git -C "$PROJ" push -q fork fm/stale; git -C "$PROJ" fetch -q fork
: > "$LOG"
run stale; state
echo "--- live worker pid $WORKER alive: $(kill -0 $WORKER 2>/dev/null && echo yes || echo NO)"
echo "--- live copy unchanged: $([ "$(git -C "$SLOT" status --porcelain)" = "$BEFORE" ] && echo yes || echo NO) ($(cat "$SLOT/live-work"))"
echo "--- slot claim: $(tr '\n' ' ' < "$LAB/pool/1/.fm-slot-owner")"

echo; echo "===== S5: no worktree= line, unpushed branch, no PR -> refuse; then --force"
fake_gh OPEN; branch_with_commit fm/s5 "s5 unlanded work"; win s5; meta s5 kind=ship mode=no-mistakes branch=fm/s5
run s5; state
run s5 --force; state

echo; echo "===== S6: two worktree= lines stay ambiguous and refuse even with --force"
win s6; meta s6 "worktree=" "worktree=$SLOT" kind=ship mode=no-mistakes branch=fm/s6
run s6 --force; state

echo; echo "===== S7: local-only record, gone worktree, branch merged into local main (no remote push)"
branch_with_commit fm/s7 "s7 local work"; g -C "$PROJ" update-ref refs/heads/main fm/s7
win s7; meta s7 "worktree=$LAB/gone" kind=ship mode=local-only branch=fm/s7
run s7; state

echo; echo "===== S8: recorded worktree directory gone, branch UNPUSHED, PR open -> refuse"
fake_gh OPEN; branch_with_commit fm/s8 "s8 unpushed work"; win s8; meta s8 "worktree=$LAB/pool/8/project" kind=ship mode=no-mistakes branch=fm/s8 pr=https://github.com/example/repo/pull/3035
run s8; state

kill $WORKER 2>/dev/null; wait $WORKER 2>/dev/null
T kill-server 2>/dev/null
"$WT_ROOT/bin/fm-lab-home.sh" teardown "$LAB" >/dev/null 2>&1
git -C "$PROJ" worktree remove --force "$SLOT" >/dev/null 2>&1
rm -rf "$LAB"; echo; echo "lab removed: $([ -e "$LAB" ] && echo no || echo yes)"

#!/usr/bin/env bash
# Manual drive: real bin/fm-spawn.sh on a real private tmux server inside a
# disposable lab FM_HOME; then a real bin/fm-control.sh relaunch. Shows the
# task_started= record a fresh spawn writes and that a relaunch carries it.
set -u
ROOT=$1
LAB=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")" && pwd -P)
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
TD=$("$ROOT/bin/fm-lab-home.sh" tmux-dir "$LAB")
cleanup() { TMUX_TMPDIR="$TD" tmux -L fm-lab kill-server 2>/dev/null; "$ROOT/bin/fm-lab-home.sh" teardown "$LAB" >/dev/null 2>&1; rm -rf "$LAB"; }
trap cleanup EXIT
PROJ=$LAB/projects/demo
mkdir -p "$PROJ" "$LAB/user-home"
git -C "$PROJ" init -q -b main; git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git init -q --bare "$LAB/demo.origin.git"; git -C "$PROJ" remote add origin "$LAB/demo.origin.git"; git -C "$PROJ" push -q origin main
printf 'claude\n' > "$LAB/config/crew-harness"
ID=refresh-z1
mkdir -p "$LAB/data/$ID"
printf '# Task\n## Captain'"'"'s intent\nRefresh PR branch.\n\n## Firstmate spec\nMerge main.\n' > "$LAB/data/$ID/brief.md"
X="env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE"
TMUX_TMPDIR="$TD" tmux -L fm-lab new-session -d -s primary -c "$ROOT" -e FM_HOME="$LAB" -e HOME="$LAB/user-home" bash --noprofile --norc
TMUX_TMPDIR="$TD" tmux -L fm-lab send-keys -t primary "$X FM_SPAWN_NO_GUARD=1 $ROOT/bin/fm-spawn.sh $ID $PROJ --mode no-mistakes --yolo off > $LAB/spawn.out 2>&1; echo DONE1 >> $LAB/spawn.out" Enter
for i in $(seq 1 90); do grep -q DONE1 "$LAB/spawn.out" 2>/dev/null && break; sleep 1; done
echo "### fresh spawn (real tmux socket fm-lab)"; cat "$LAB/spawn.out"
echo "--- state/$ID.meta (task_started / spawn_gen)"; grep -E '^(task_started|spawn_gen|worktree|harness)=' "$LAB/state/$ID.meta"
S1=$(grep '^task_started=' "$LAB/state/$ID.meta" | cut -d= -f2)
sleep 2
TMUX_TMPDIR="$TD" tmux -L fm-lab send-keys -t primary "$X $ROOT/bin/fm-control.sh $ID relaunch --note 'continuing after stall' > $LAB/rl.out 2>&1; echo DONE2 rc=\$? >> $LAB/rl.out" Enter
for i in $(seq 1 90); do grep -q DONE2 "$LAB/rl.out" 2>/dev/null && break; sleep 1; done
echo; echo "### relaunch"; cat "$LAB/rl.out"
echo "--- state/$ID.meta after relaunch"; grep -E '^(task_started|spawn_gen)=' "$LAB/state/$ID.meta"
S2=$(grep '^task_started=' "$LAB/state/$ID.meta" | cut -d= -f2)
echo; echo "task_started fresh=$S1 after-relaunch=$S2 count=$(grep -c '^task_started=' "$LAB/state/$ID.meta")"
TMUX_TMPDIR="$TD" tmux -L fm-lab list-windows -a -F '#S:#W'

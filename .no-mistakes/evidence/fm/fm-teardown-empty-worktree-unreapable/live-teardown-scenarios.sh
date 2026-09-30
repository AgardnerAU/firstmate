#!/usr/bin/env bash
# Live driver: real bin/fm-teardown.sh against a disposable fm-lab home, a real
# private tmux server, real git repos. treehouse is replaced by a probe that
# logs any call (none may happen on these paths). Usage: <script> <fm-root>
set -u
FMROOT=$1
TD="$FMROOT/bin/fm-teardown.sh"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$FMROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/tmux" "$LAB/probe" "$LAB/fx"
export TMUX_TMPDIR="$LAB/tmux"; unset TMUX
cat > "$LAB/probe/treehouse" <<SH
#!/usr/bin/env bash
echo "treehouse \$*" >> "$LAB/probe/treehouse.log"; exit 1
SH
chmod +x "$LAB/probe/treehouse"
PATH="$LAB/probe:$PATH"
cleanup() { tmux kill-server 2>/dev/null; rm -rf "$LAB"; }
trap cleanup EXIT
tmux new-session -d -s firstmate -n keep sleep 3600
g() { git -c user.name=t -c user.email=t@example.invalid "$@"; }
S=$LAB/state
td() { env -u NO_MISTAKES_GATE -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE FM_HOME="$LAB" "$TD" "$@"; }
win() { tmux new-window -d -t firstmate -n "fm-$1" sleep 3600; }
haswin() { tmux list-windows -t firstmate -F '#W' | grep -qx "fm-$1" && echo "window fm-$1: present" || echo "window fm-$1: closed"; }
meta() { local f=$S/$1.meta; shift; printf '%s\n' "$@" > "$f"; }
rec() { [ -e "$S/$1.meta" ] && echo "record $1: present" || echo "record $1: removed"; }
run() { echo "\$ fm-teardown.sh $*"; td "$@"; echo "[exit $?]"; }
hdr() { echo; echo "=================== $* ==================="; }

# Project repo with a bare origin, main pushed.
P=$LAB/fx/project; g init -q -b main "$P"; g -C "$P" commit -q --allow-empty -m base
g init -q --bare "$LAB/fx/origin.git"; g -C "$P" remote add origin "$LAB/fx/origin.git"; g -C "$P" push -q origin main
newbranch() { g -C "$P" branch "$1" main; local t; t=$(g -C "$P" mktree < <(printf '100644 blob %s\t%s\n' "$(echo "$1 work" | g -C "$P" hash-object -w --stdin)" "${1//\//-}.txt")); g -C "$P" update-ref "refs/heads/$1" "$(g -C "$P" commit-tree -p "$1" -m "$2" "$t")"; }

# Treehouse pool with slot 1 checked out, owned (claim) by live-task.
POOL=$LAB/fx/pool; mkdir -p "$POOL/1"; g -C "$P" worktree add -q --detach "$POOL/1/project"
printf '{"worktrees":[{"name":"1","path":"%s"}]}\n' "$POOL/1/project" > "$POOL/treehouse-state.json"
SLOT=$POOL/1/project

hdr "S1 slot held by another live task: stale record, unpushed branch"
newbranch fm/stale "stale task unpushed work"
meta stale-task window=firstmate:fm-stale-task endpoint_task_id=stale-task "worktree=$SLOT" "project=$P" kind=ship mode=no-mistakes branch=fm/stale spawn_gen=g1
meta live-task window=firstmate:fm-live-task endpoint_task_id=live-task "worktree=$SLOT" "project=$P" kind=ship mode=no-mistakes branch=fm/live spawn_gen=g2
printf 'task=live-task\nhome=%s\n' "$LAB" > "$POOL/1/.fm-slot-owner"
win stale-task; win live-task
echo "live uncommitted edit" > "$SLOT/live-work"
( cd "$SLOT" && exec sleep 3600 ) & WORKER=$!
BEFORE=$(g -C "$SLOT" status --porcelain)
run stale-task
rec stale-task; rec live-task; haswin stale-task; haswin live-task
kill -0 $WORKER && echo "live worker pid $WORKER: alive"
[ "$(g -C "$SLOT" status --porcelain)" = "$BEFORE" ] && echo "live copy status: unchanged ($BEFORE)"

hdr "S1b same record after its branch is pushed to a fork"
g init -q --bare "$LAB/fx/fork.git"; g -C "$P" remote add fork "$LAB/fx/fork.git"; g -C "$P" push -q fork fm/stale
run stale-task
rec stale-task; rec live-task; haswin stale-task; haswin live-task
kill -0 $WORKER && echo "live worker pid $WORKER: alive"
[ "$(g -C "$SLOT" status --porcelain)" = "$BEFORE" ] && echo "live copy status: unchanged ($BEFORE)"
echo "slot claim: $(tr '\n' ' ' < "$POOL/1/.fm-slot-owner")"
kill $WORKER; wait $WORKER 2>/dev/null

hdr "S2 recorded worktree directory no longer exists, branch pushed"
newbranch fm/gone "gone task work"; g -C "$P" push -q origin fm/gone
meta gone-task window=firstmate:fm-gone-task endpoint_task_id=gone-task "worktree=$POOL/2/project" "project=$P" kind=ship mode=no-mistakes branch=fm/gone spawn_gen=g3
win gone-task
run gone-task
rec gone-task; haswin gone-task

hdr "S3 cleared worktree= line, branch has unpushed commits: refuse, then --force"
newbranch fm/cleared "cleared task unlanded work"
meta cleared-task window=firstmate:fm-cleared-task endpoint_task_id=cleared-task "worktree=" "project=$P" kind=ship mode=no-mistakes branch=fm/cleared spawn_gen=g4
win cleared-task
run cleared-task
rec cleared-task; haswin cleared-task
run cleared-task --force
rec cleared-task; haswin cleared-task

hdr "S4 no worktree= line at all, branch pushed with PR open"
newbranch fm/nowt "nowt task work"; g -C "$P" push -q origin fm/nowt
meta nowt-task window=firstmate:fm-nowt-task endpoint_task_id=nowt-task "project=$P" kind=ship mode=no-mistakes branch=fm/nowt spawn_gen=g5
win nowt-task
run nowt-task
rec nowt-task; haswin nowt-task

hdr "S5 local-only record with no worktree, branch fast-forwarded into local main (origin exists)"
newbranch fm/local "local-only merged work"
g -C "$P" update-ref refs/heads/main refs/heads/fm/local
meta local-task window=firstmate:fm-local-task endpoint_task_id=local-task "worktree=" "project=$P" kind=ship mode=local-only branch=fm/local spawn_gen=g6
win local-task
run local-task
rec local-task; haswin local-task

hdr "S6 adversarial: two worktree= lines (ambiguous) refuse even with --force"
meta amb-task window=firstmate:fm-amb-task endpoint_task_id=amb-task "worktree=" "worktree=$SLOT" "project=$P" kind=ship mode=no-mistakes branch=fm/gone spawn_gen=g7
win amb-task
run amb-task --force
rec amb-task; haswin amb-task

hdr "S7 adversarial: slot claim names THIS task while another record names it: collision still refuses"
printf 'task=mine-task\nhome=%s\n' "$LAB" > "$POOL/1/.fm-slot-owner"
meta mine-task window=firstmate:fm-mine-task endpoint_task_id=mine-task "worktree=$SLOT" "project=$P" kind=ship mode=no-mistakes branch=fm/gone spawn_gen=g8
win mine-task
run mine-task --force
rec mine-task; rec live-task; haswin mine-task; [ -e "$SLOT/live-work" ] && echo "live copy edit: still present"

hdr "treehouse probe calls"
cat "$LAB/probe/treehouse.log" 2>/dev/null || echo "(none)"

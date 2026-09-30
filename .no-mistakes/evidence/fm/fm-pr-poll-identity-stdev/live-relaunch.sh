#!/usr/bin/env bash
# Live driver: a real Claude worker spawned by bin/fm-spawn.sh inside the
# fm-live-lab lab (private tmux server). Arm a merge poll on it, then run the
# real `fm-control.sh <id> relaunch`, which exits and relaunches the worker, and
# prove the poll still authenticates and the real watcher reports the merge.
set -u
ROOT=$PWD
EV=/Users/agardner/.no-mistakes/evidence/01M3SMCB52SV79Z4NHS0B46ETT
LABROOT=/private/tmp/fmlab-prpoll; L=$LABROOT/home
W=$(sed -n 's/^worker_id=//p' $LABROOT/.fm-live-lab); TD=$(sed -n 's/^tmux_dir=//p' $LABROOT/.fm-live-lab)
FAKE=$LABROOT/fakebin; mkdir -p $FAKE; cp $EV/gh-stub.sh $FAKE/gh; chmod +x $FAKE/gh
lab() { env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" PATH="$PATH" SHELL=/bin/zsh TERM=xterm-256color LANG=en_US.UTF-8 \
  TMUX_TMPDIR="$TD" TREEHOUSE_ROOT="$LABROOT/treehouse" FM_BACKEND=tmux DISABLE_AUTOUPDATER=1 FM_HOME="$L" "$@"; }
META=$L/state/$W.meta; URL=https://github.com/example/notes/pull/31
WT=$(sed -n 's/^worktree=//p' $META); HEAD=$(git -C "$WT" rev-parse HEAD)
echo "## 1. record the PR on the real worker's task record and arm the poll (fm-pr-lib publish path used by fm-pr-check.sh)"
printf 'pr=%s\npr_head=%s\n' "$URL" "$HEAD" >> $META
lab bash -c '. "$1/bin/fm-pr-lib.sh"; fm_pr_url_parse "$2" && fm_pr_poll_prepare "$3" "$4" "$FM_PR_PROVIDER" "$2" "$FM_PR_HOST" "$FM_PR_PATH" "$FM_PR_NUMBER" "$1/bin/fm-pr-poll.sh" && fm_pr_poll_publish_prepared' _ "$L" "$URL" "$L/state" "$W" && echo armed
valid() { lab bash -c '. "$1/bin/fm-pr-lib.sh"; if fm_pr_poll_artifacts_valid "$2" "$3" "$1/bin/fm-pr-poll.sh"; then echo "poll authenticates: yes"; else echo "poll authenticates: NO ($FM_PR_POLL_REJECTION)"; fi' _ "$L" "$L/state" "$W"; }
valid
pane_before=$(TMUX_TMPDIR=$TD tmux display-message -p -t "firstmate:fm-$W" '#{pane_pid}')
spawn_before=$(sed -n 's/^spawn_gen=//p' $META)
echo "## 2. real relaunch: fm-control.sh $W relaunch"
lab bash -c 'cd "$1" && bin/fm-control.sh "$2" relaunch --note "live test: relaunch over an armed merge poll"' _ "$L" "$W" 2>&1 | tail -8
echo "relaunch rc=${PIPESTATUS[0]}"
pane_after=$(TMUX_TMPDIR=$TD tmux display-message -p -t "firstmate:fm-$W" '#{pane_pid}' 2>&1)
echo "worker pane pid before=$pane_before after=$pane_after; spawn_gen before=$spawn_before after=$(sed -n 's/^spawn_gen=//p' $META)"
echo "--- relaunched task record:"; cat $META
valid
echo "## 3. real fm-watch.sh cycle, forge reporting MERGED"
lab env PATH="$FAKE:$PATH" FM_TEST_GH_LOG=$LABROOT/gh.log FM_TEST_GH_STATE=MERGED FM_CHECK_INTERVAL=0 FM_POLL=0.02 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 \
  perl -e 'alarm 90; exec @ARGV' "$L/bin/fm-watch.sh" > $LABROOT/watch.out 2>$LABROOT/watch.err; echo "watch rc=$?"
cat $LABROOT/watch.out

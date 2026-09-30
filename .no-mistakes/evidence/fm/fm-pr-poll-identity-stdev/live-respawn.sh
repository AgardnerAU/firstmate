#!/usr/bin/env bash
# Live driver: fresh re-spawn (bin/fm-spawn.sh, not --relaunch) of the real
# lab worker while its merge poll is armed. The old worker window is killed
# first, standing in for a dead worker the firstmate re-spawns.
set -u
EV=/Users/agardner/.no-mistakes/evidence/01M3SMCB52SV79Z4NHS0B46ETT
LABROOT=/private/tmp/fmlab-prpoll; L=$LABROOT/home
W=$(sed -n 's/^worker_id=//p' $LABROOT/.fm-live-lab); TD=$(sed -n 's/^tmux_dir=//p' $LABROOT/.fm-live-lab)
FAKE=$LABROOT/fakebin
lab() { env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" PATH="$PATH" SHELL=/bin/zsh TERM=xterm-256color LANG=en_US.UTF-8 \
  TMUX_TMPDIR="$TD" TREEHOUSE_ROOT="$LABROOT/treehouse" FM_BACKEND=tmux DISABLE_AUTOUPDATER=1 FM_HOME="$L" "$@"; }
META=$L/state/$W.meta; URL=https://github.com/example/notes/pull/32
valid() { lab bash -c '. "$1/bin/fm-pr-lib.sh"; if fm_pr_poll_artifacts_valid "$2" "$3" "$1/bin/fm-pr-poll.sh"; then echo "poll authenticates: yes"; else echo "poll authenticates: NO ($FM_PR_POLL_REJECTION)"; fi' _ "$L" "$L/state" "$W"; }
echo "## 1. re-arm a merge poll on the worker (task record gets a fresh pr= block)"
grep -v '^pr' $META > $META.t && mv $META.t $META && chmod 600 $META
printf 'pr=%s\npr_head=%s\n' "$URL" "$(sed -n 's/^worktree=//p' $META | xargs git -C 2>/dev/null rev-parse HEAD || echo 0123456789abcdef0123456789abcdef01234567)" >> $META
lab bash -c '. "$1/bin/fm-pr-lib.sh"; fm_pr_url_parse "$2" && fm_pr_poll_prepare "$3" "$4" "$FM_PR_PROVIDER" "$2" "$FM_PR_HOST" "$FM_PR_PATH" "$FM_PR_NUMBER" "$1/bin/fm-pr-poll.sh" && fm_pr_poll_publish_prepared' _ "$L" "$URL" "$L/state" "$W" && echo armed
valid
spawn_before=$(sed -n 's/^spawn_gen=//p' $META)
echo "## 2. the worker dies: kill its tmux window"
TMUX_TMPDIR=$TD tmux kill-window -t "firstmate:fm-$W"
echo "## 3. real fresh re-spawn: fm-spawn.sh $W projects/notes --mode local-only --yolo on --harness claude"
(cd $L && lab "$L/bin/fm-spawn.sh" "$W" "$L/projects/notes" --mode local-only --yolo on --harness claude --model sonnet --effort low) 2>&1 | grep -v '^●' | tail -6
echo "spawn rc=${PIPESTATUS[0]}; spawn_gen before=$spawn_before after=$(sed -n 's/^spawn_gen=//p' $META)"
echo "--- republished task record:"; cat $META
valid
echo "## 4. real fm-watch.sh cycle, forge reporting MERGED"
lab env PATH="$FAKE:$PATH" FM_TEST_GH_LOG=$LABROOT/gh.log FM_TEST_GH_STATE=MERGED FM_CHECK_INTERVAL=0 FM_POLL=0.02 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 \
  perl -e 'alarm 90; exec @ARGV' "$L/bin/fm-watch.sh" > $LABROOT/watch2.out 2>$LABROOT/watch2.err; echo "watch rc=$?"
cat $LABROOT/watch2.out
TMUX_TMPDIR=$TD tmux list-windows -t firstmate -F '#{window_name} #{pane_current_command}'

#!/usr/bin/env bash
# Live driver: captain-hold completion attestation (bin/fm-captain-hold.sh
# complete <id> --none) on the real lab worker task while its merge poll is armed.
set -u
LABROOT=/private/tmp/fmlab-prpoll; L=$LABROOT/home; TD=/tmp/fml.ZH9qSU
W=$(sed -n 's/^worker_id=//p' $LABROOT/.fm-live-lab)
E() { env -i HOME="$HOME" USER="$USER" PATH="$LABROOT/fakebin:$PATH" TMUX_TMPDIR="$TD" FM_BACKEND=tmux FM_HOME="$L" "$@"; }
META=$L/state/$W.meta; URL=https://github.com/example/notes/pull/33
valid() { E bash -c '. "$1/bin/fm-pr-lib.sh"; if fm_pr_poll_artifacts_valid "$2" "$3" "$1/bin/fm-pr-poll.sh"; then echo "poll authenticates: yes"; else echo "poll authenticates: NO ($FM_PR_POLL_REJECTION)"; fi' _ "$L" "$L/state" "$W"; }
grep -v '^pr' $META > $META.t && mv $META.t $META && chmod 600 $META
printf 'pr=%s\npr_head=0123456789abcdef0123456789abcdef01234567\n' "$URL" >> $META
E bash -c '. "$1/bin/fm-pr-lib.sh"; fm_pr_url_parse "$2" && fm_pr_poll_prepare "$3" "$4" "$FM_PR_PROVIDER" "$2" "$FM_PR_HOST" "$FM_PR_PATH" "$FM_PR_NUMBER" "$1/bin/fm-pr-poll.sh" && fm_pr_poll_publish_prepared' _ "$L" "$URL" "$L/state" "$W" && echo armed
valid
echo "## fm-captain-hold.sh complete $W --none"
(cd $L && E "$L/bin/fm-captain-hold.sh" complete "$W" --none) 2>&1 | grep -v '^●' | tail -4; echo "rc=${PIPESTATUS[0]}"
echo "--- record tail:"; tail -n 4 $META
valid

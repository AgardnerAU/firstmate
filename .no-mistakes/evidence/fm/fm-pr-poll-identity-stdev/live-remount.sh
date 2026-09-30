#!/usr/bin/env bash
# Live scenario driver: real fm-pr-check.sh arms a poll in a disposable lab
# home, the registration is aged to look like a pre-remount record (recorded
# st_dev != live st_dev), then the real fm-watch.sh runs against it.
set -u
ROOT=$PWD
EV=/Users/agardner/.no-mistakes/evidence/01M3SMCB52SV79Z4NHS0B46ETT
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
unset NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
bin/fm-lab-home.sh create "$LAB" >/dev/null
mkdir -p "$LAB/fakebin" "$LAB/wt"
cp "$EV/gh-stub.sh" "$LAB/fakebin/gh"; chmod +x "$LAB/fakebin/gh"
export FM_TEST_GH_LOG="$LAB/gh.log"
git -C "$LAB/wt" init -q; git -C "$LAB/wt" commit -q --allow-empty -m init
ID=live-remount; URL=https://github.com/example/repo/pull/11
printf '%s\n' "window=fm-lab:fm-$ID" "endpoint_task_id=$ID" "worktree=$LAB/wt" "project=$LAB/wt" kind=ship mode=no-mistakes > "$LAB/state/$ID.meta"
BASEPATH="$LAB/fakebin:$PATH"
echo "## 1. arm the merge watch with the real fm-pr-check.sh"
FM_HOME="$LAB" PATH="$BASEPATH" bin/fm-pr-check.sh "$ID" "$URL"; echo "rc=$?"
echo "--- task record tail:"; tail -n 2 "$LAB/state/$ID.meta"
dev=$(stat -f %d "$LAB/state")
echo "--- live state st_dev=$dev; registration identities as armed:"; sed -n '10,11p' "$LAB/state/$ID.pr-poll-registration"
echo "## 2. simulate the APFS reboot renumbering: rewrite the recorded device ($dev -> $((dev+3))), inodes/bytes untouched"
reg="$LAB/state/$ID.pr-poll-registration"; tmp="$LAB/state/.reg.tmp"
awk -v d="$dev" -v n="$((dev+3))" '(NR==10||NR==11){sub("^" d ":", n ":")} {print}' "$reg" > "$tmp"; chmod 600 "$tmp"; mv -f "$tmp" "$reg"
sed -n '10,11p' "$reg"
run_watch() {
  perl -e 'alarm 60; exec @ARGV' env FM_HOME="$LAB" FM_CHECK_INTERVAL=0 FM_POLL=0.02 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 \
    PATH="$BASEPATH" FM_TEST_GH_STATE="$1" bin/fm-watch.sh
}
echo "## 3. real fm-watch.sh cycle with the forge reporting MERGED"
run_watch MERGED > "$LAB/watch.out" 2> "$LAB/watch.err"; echo "watch rc=$?"
echo "--- watcher wake output:"; cat "$LAB/watch.out"
echo "--- poll artifacts after merge:"; ls "$LAB/state" | grep "$ID" || true
echo "--- registration still re-recorded? (should be gone after retirement)"; [ -e "$reg" ] && sed -n '10,11p' "$reg" || echo "(registration retired)"

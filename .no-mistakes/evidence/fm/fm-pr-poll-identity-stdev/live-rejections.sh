#!/usr/bin/env bash
# Adversarial live driver: after a simulated remount, a REPLACED sidecar
# (byte-identical copy, new inode) must still be refused, and every refusal
# must name its cause in the watcher wake.
set -u
EV=/Users/agardner/.no-mistakes/evidence/01M3SMCB52SV79Z4NHS0B46ETT
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
unset NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
bin/fm-lab-home.sh create "$LAB" >/dev/null
mkdir -p "$LAB/fakebin" "$LAB/wt"
cp "$EV/gh-stub.sh" "$LAB/fakebin/gh"; chmod +x "$LAB/fakebin/gh"
export FM_TEST_GH_LOG="$LAB/gh.log" FM_GUARD_QUIET=1
git -C "$LAB/wt" init -q; git -C "$LAB/wt" commit -q --allow-empty -m init
BASEPATH="$LAB/fakebin:$PATH"
arm() {  # id url
  printf '%s\n' "window=fm-lab:fm-$1" "endpoint_task_id=$1" "worktree=$LAB/wt" "project=$LAB/wt" kind=ship mode=no-mistakes > "$LAB/state/$1.meta"
  FM_HOME="$LAB" PATH="$BASEPATH" bin/fm-pr-check.sh "$1" "$2" 2>/dev/null | grep armed
}
dev=$(stat -f %d "$LAB/state")
shiftdev() { local reg="$LAB/state/$1.pr-poll-registration"; awk -v d="$dev" -v n="$((dev+3))" '(NR==10||NR==11){sub("^" d ":", n ":")} {print}' "$reg" > "$LAB/state/.t"; chmod 600 "$LAB/state/.t"; mv -f "$LAB/state/.t" "$reg"; }
echo "## A. remount + sidecar replaced by a byte-identical copy (new inode)"
arm replaced https://github.com/example/repo/pull/21
shiftdev replaced
cp -p "$LAB/state/replaced.pr-poll" "$LAB/state/.copy"; mv -f "$LAB/state/.copy" "$LAB/state/replaced.pr-poll"; chmod 600 "$LAB/state/replaced.pr-poll"
echo "## B. armed poll whose task record lost its pr= line (the old respawn symptom)"
arm nopr https://github.com/example/repo/pull/22
grep -v '^pr' "$LAB/state/nopr.meta" > "$LAB/state/.m"; mv -f "$LAB/state/.m" "$LAB/state/nopr.meta"
echo "## C. armed poll whose task record has a key after pr= (the old relaunch symptom)"
arm afterpr https://github.com/example/repo/pull/23
echo "control_relaunch_tx=abc" >> "$LAB/state/afterpr.meta"
echo "## real fm-watch.sh cycle (forge says MERGED for all)"
perl -e 'alarm 60; exec @ARGV' env FM_HOME="$LAB" FM_CHECK_INTERVAL=0 FM_POLL=0.02 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 \
  PATH="$BASEPATH" FM_TEST_GH_STATE=MERGED bin/fm-watch.sh > "$LAB/watch.out" 2>"$LAB/watch.err"; echo "watch rc=$?"
sed "s#$LAB#\$LAB#g" "$LAB/watch.out" | tr ';' '\n'
echo "--- merge-state reads by the watcher (a refused check must never run): $(grep -c -- '--json state' "$LAB/gh.log")"
echo "--- all gh calls (arming reads only):"; cat "$LAB/gh.log"

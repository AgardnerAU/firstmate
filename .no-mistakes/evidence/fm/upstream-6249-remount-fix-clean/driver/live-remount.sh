#!/usr/bin/env bash
# Live driver: real bin/fm-watch.sh against a disposable lab FM_HOME.
# Only gh (external forge boundary) is faked.
set -u
ROOT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
FB=$LAB/fakebin; mkdir -p "$FB" "$LAB/wt"
git -C "$LAB/wt" init -q; git -C "$LAB/wt" commit -q --allow-empty -m init
cat > "$FB/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case " $* " in *" pr view "*"--json state "*) echo "${GH_STATE:-OPEN}";; esac
SH
chmod +x "$FB/gh"
N=0
fresh() { N=$((N+1)); H=$LAB/home$N; "$ROOT/bin/fm-lab-home.sh" create "$H" >/dev/null || { echo "lab create failed"; exit 1; }; S=$H/state; : > "$LAB/gh.log"; }
fresh
. "$ROOT/bin/fm-pr-lib.sh"
arm() { # id url
  printf 'window=fm-%s\nworktree=%s\nkind=ship\npr=%s\n' "$1" "$LAB/wt" "$2" > "$S/$1.meta"; chmod 600 "$S/$1.meta"
  fm_pr_url_parse "$2" && fm_pr_poll_prepare "$S" "$1" "$FM_PR_PROVIDER" "$2" "$FM_PR_HOST" "$FM_PR_PATH" "$FM_PR_NUMBER" "$ROOT/bin/fm-pr-poll.sh" && fm_pr_poll_publish_prepared
}
renumber() { # id : rewrite recorded device as a reboot would leave it
  local reg=$S/$1.pr-poll-registration dev tmp; dev=$(fm_pr_file_device "$S")
  tmp=$(mktemp "$S/.tmp.XXXXXX"); sed -E "s/^${dev}:([0-9]+)$/$((dev+7)):\1/" "$reg" > "$tmp"; chmod 600 "$tmp"; mv -f "$tmp" "$reg"
}
watch_once() { # out-file [gh-state]
  if [ "${NOSTOP:-0}" = 0 ]; then printf '#!/usr/bin/env bash\necho stop-cycle\n' > "$S/zz-stop.check.sh"; chmod 700 "$S/zz-stop.check.sh"
  FM_HOME=$H "$ROOT/bin/fm-check-register.sh" zz-stop >/dev/null; fi
  env -u NO_MISTAKES_GATE -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE GH_LOG=$LAB/gh.log GH_STATE=${2:-OPEN} FM_HOME=$H FM_CHECK_INTERVAL=0 FM_POLL=0.02 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 PATH="$FB:$PATH" \
    timeout 60 "$ROOT/bin/fm-watch.sh" > "$1" 2>"$1.err"; echo "watcher exit=$?"
}
echo "### Lab state dir device: $(fm_pr_file_device "$S")"
echo; echo "=== S1: armed poll survives device renumbering (PR still OPEN) ==="
arm t-open https://github.com/o/r/pull/11
renumber t-open
echo "registration identity lines after simulated reboot:"; grep -E '^[0-9]+:[0-9]+$' "$S/t-open.pr-poll-registration"
watch_once "$LAB/w1.out" OPEN; echo "--- watcher wake output:"; cat "$LAB/w1.out"
echo "--- gh calls:"; cat "$LAB/gh.log"
grep -q 'rejected unauthenticated' "$LAB/w1.out" && echo "S1 RESULT: FAIL (rejected)" || { grep -q 'pr view https://github.com/o/r/pull/11 --json state' "$LAB/gh.log" && [ -e "$S/t-open.check.sh" ] && echo "S1 RESULT: PASS (poll ran, still armed, no rejection)" || echo "S1 RESULT: FAIL"; }
rm -f "$S"/t-open.*
fresh; echo; echo "=== S2: renumbered poll detects merge and retires ==="
: > "$LAB/gh.log"; arm t-merged https://github.com/o/r/pull/12; renumber t-merged
watch_once "$LAB/w2.out" MERGED; echo "--- watcher wake output:"; cat "$LAB/w2.out"
grep -q 't-merged.check.sh: merged' "$LAB/w2.out" && [ ! -e "$S/t-merged.check.sh" ] && echo "S2 RESULT: PASS (merge surfaced, poll retired)" || echo "S2 RESULT: FAIL"
fresh; echo; echo "=== S3 (adversarial): byte-identical replaced check after renumber is refused with cause ==="
: > "$LAB/gh.log"; arm t-swap https://github.com/o/r/pull/13; renumber t-swap
cp -p "$S/t-swap.check.sh" "$S/.x"; mv -f "$S/.x" "$S/t-swap.check.sh"
NOSTOP=1 watch_once "$LAB/w3.out" MERGED; echo "--- watcher wake output:"; cat "$LAB/w3.out"
echo "--- gh calls:"; cat "$LAB/gh.log"
grep -q 't-swap.check.sh (merge poll: the sidecar or check is not the file its registration was armed with)' "$LAB/w3.out" && ! grep -q pull/13 "$LAB/gh.log" && echo "S3 RESULT: PASS (refused, cause named, never executed)" || echo "S3 RESULT: FAIL"
rm -f "$S"/t-swap.*
fresh; echo; echo "=== S4: unregistered custom check rejection names its cause ==="
printf '#!/usr/bin/env bash\necho hi\n' > "$S/rogue.check.sh"; chmod 700 "$S/rogue.check.sh"
NOSTOP=1 watch_once "$LAB/w4.out"; echo "--- watcher wake output:"; cat "$LAB/w4.out"
grep -q 'rogue.check.sh (custom check: it is not registered (bin/fm-check-register.sh))' "$LAB/w4.out" && echo "S4 RESULT: PASS" || echo "S4 RESULT: FAIL"
rm -f "$S/rogue.check.sh"
fresh; echo; echo "=== S5: merge poll whose task record has a key after pr= is refused naming it ==="
arm t-meta https://github.com/o/r/pull/14; echo "model=opus" >> "$S/t-meta.meta"
NOSTOP=1 watch_once "$LAB/w5.out"; echo "--- watcher wake output:"; cat "$LAB/w5.out"
grep -q 't-meta.check.sh (merge poll: .*model' "$LAB/w5.out" && echo "S5 RESULT: PASS" || echo "S5 RESULT: FAIL"

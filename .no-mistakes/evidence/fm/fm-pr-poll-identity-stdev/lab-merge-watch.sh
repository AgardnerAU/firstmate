#!/usr/bin/env bash
# Live lab: arm a real merge poll with bin/fm-pr-check.sh in a disposable
# FM_HOME, then drive bin/fm-watch.sh across a simulated APFS device renumber,
# a replaced check file, a key appended after pr=, and captain attestation.
set -u
ROOT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
trap 'chmod -R u+w "$LAB" 2>/dev/null; rm -rf "$LAB"' EXIT
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
S="$LAB/state"; FB="$LAB/fakebin"; mkdir -p "$FB"
cat > "$FB/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" --json isDraft "*) echo '{"isDraft":false}' ;;
  *" --json state "*) echo "${FM_LAB_GH_STATE:-OPEN}"; echo "gh $*" >> "${FM_LAB_GH_LOG:-/dev/null}" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$FB/gh"
P="$FB:$PATH"
. "$ROOT/bin/fm-pr-lib.sh"

watch_once() { # <label> <gh-state>: up to 4 watcher cycles, draining queued wakes between them
  local i; : > "$LAB/w.out"
  for i in 1 2 3 4; do
    FM_HOME="$LAB" PATH="$P" "$ROOT/bin/fm-wake-drain.sh" >/dev/null 2>&1 || true
    FM_LAB_GH_STATE=$2 FM_LAB_GH_LOG="$LAB/gh.log" PATH="$P" FM_HOME="$LAB" FM_CHECK_INTERVAL=0 \
      FM_POLL=0.02 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 \
      perl -e 'alarm 60; exec @ARGV' "$ROOT/bin/fm-watch.sh" > "$LAB/w1.out" 2>"$LAB/w.err"
    cat "$LAB/w1.out" >> "$LAB/w.out"
    grep -q 'stop-cycle\|rejected unauthenticated' "$LAB/w1.out" && break
  done
  echo "--- fm-watch.sh output ($1):"; sed 's/^/    /' "$LAB/w.out"
}
stop_check() {
  printf '#!/usr/bin/env bash\nprintf "stop-cycle\\n"\n' > "$S/z-stop.check.sh"; chmod 0700 "$S/z-stop.check.sh"
  FM_HOME="$LAB" "$ROOT/bin/fm-check-register.sh" z-stop >/dev/null
}
arm() { # <id> <url>
  printf 'window=fm-%s\nkind=ship\nmode=direct\n' "$1" > "$S/$1.meta"; chmod 600 "$S/$1.meta"
  PATH="$P" FM_HOME="$LAB" "$ROOT/bin/fm-pr-check.sh" "$1" "$2" 2>&1 | sed 's/^/    fm-pr-check: /'
}
shift_device() { # <id>: rewrite recorded device numbers (lines 10,11) the way an APFS remount leaves them
  local r="$S/$1.pr-poll-registration" d; d=$(fm_pr_file_device "$S")
  awk -v live="$d" -v n="$((d+3))" 'NR==10||NR==11{sub("^" live ":", n ":")}{print}' "$r" > "$S/.tmpreg"
  chmod 600 "$S/.tmpreg"; mv -f "$S/.tmpreg" "$r"
  echo "    live state device: $d; registration now records: $(sed -n 10p "$r") / $(sed -n 11p "$r")"
}

echo "=== Scenario 1: armed poll survives a device renumber (open PR, then merged)"
arm t1 https://github.com/o/r/pull/11
echo "    task record tail: $(tail -n1 "$S/t1.meta")"
shift_device t1
stop_check
watch_once "renumbered, PR open" OPEN
grep -q 'rejected unauthenticated' "$LAB/w.out" && echo "RESULT S1a: FAIL (rejected)" || echo "RESULT S1a: PASS (no rejection; poll ran: $(grep -c 'pull/11' "$LAB/gh.log" 2>/dev/null) gh state query)"
watch_once "renumbered, PR merged" MERGED
grep -q 't1.check.sh: merged' "$LAB/w.out" && [ ! -e "$S/t1.pr-poll-registration" ] && echo "RESULT S1b: PASS (merge detected, poll retired)" || echo "RESULT S1b: FAIL"

echo "=== Scenario 2 (adversarial): renumbered poll whose check file was replaced is still refused, with cause"
arm t2 https://github.com/o/r/pull/12
shift_device t2
cp "$S/t2.check.sh" "$S/.swap"; chmod 600 "$S/.swap"; mv -f "$S/.swap" "$S/t2.check.sh"
rm -f "$S"/z-stop.*; watch_once "replaced check" OPEN
grep -q 't2.check.sh (merge poll: the sidecar or check is not the file its registration was armed with)' "$LAB/w.out" && echo "RESULT S2: PASS" || echo "RESULT S2: FAIL"
rm -f "$S"/t2.*; stop_check

echo "=== Scenario 3: a key appended after pr= is rejected and the wake names the cause"
arm t3 https://github.com/o/r/pull/13
printf 'control_relaunch_tx=tx-1\n' >> "$S/t3.meta"
rm -f "$S"/z-stop.*; watch_once "key after pr=" OPEN
grep -q 't3.check.sh (merge poll: the task record has key control_relaunch_tx after its pr= block)' "$LAB/w.out" && echo "RESULT S3: PASS" || echo "RESULT S3: FAIL"
rm -f "$S"/t3.*; stop_check

echo "=== Scenario 4: captain attestation (fm-captain-hold.sh complete) under umask 022 keeps pr= last, 0600, poll valid"
arm t4 https://github.com/o/r/pull/14
FM_HOME="$LAB" "$ROOT/bin/tasks-axi" add t4 "Sample ship" --kind ship --repo sample --start >/dev/null 2>&1 || true
printf 'done: shipped\n' > "$S/t4.status"
(umask 022; FM_HOME="$LAB" PATH="$P" "$ROOT/bin/fm-captain-hold.sh" complete t4 --none 2>&1 | sed 's/^/    captain-hold: /')
echo "    record: $(tr '\n' '|' < "$S/t4.meta")  mode: $(stat -f %Lp "$S/t4.meta")"
watch_once "after attestation" OPEN
grep -q 'decisions_reviewed=1' "$S/t4.meta" && [ "$(stat -f %Lp "$S/t4.meta")" = 600 ] && [ "$(tail -n1 "$S/t4.meta")" = pr=https://github.com/o/r/pull/14 ] && ! grep -q rejected "$LAB/w.out" \
  && echo "RESULT S4: PASS" || echo "RESULT S4: FAIL"

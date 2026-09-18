#!/usr/bin/env bash
# Manual end-user drive of the supervision chain changed on this branch.
# Stands up throwaway crew homes + real git worktrees, a fake `no-mistakes` CLI
# (the external dependency, not the product), and runs the REAL
# bin/fm-crew-state.sh and the REAL bin/fm-inactive-reconcile.sh.
set -u
ROOT=${ROOT:?}
CREW_STATE="$ROOT/bin/fm-crew-state.sh"
RECON="$ROOT/bin/fm-inactive-reconcile.sh"
W=${W:?}
mkdir -p "$W"

mk_fakebin() { # <dir>
  local fb=$1/fakebin; mkdir -p "$fb"
  cat > "$fb/no-mistakes" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  axi) shift
    if [ "$#" = 0 ]; then printf '%s\n' "${FM_FAKE_AXI_STATUS:-}"; exit 0; fi
    case "${1:-}" in
      status) shift
        if [ "${1:-}" = --run ]; then printf '%s\n' "${FM_FAKE_AXI_STATUS_RUN:-}"; else printf '%s\n' "${FM_FAKE_AXI_STATUS:-}"; fi ;;
      logs) printf '%s\n' "${FM_FAKE_CI_LOGS:-}" ;;
    esac ;;
  runs) printf '%s\n' "${FM_FAKE_RUNS_LIST:-}" ;;
  daemon) printf 'daemon running (pid 4242)\n'; exit 0 ;;
esac
exit 0
SH
  cat > "$fb/tmux" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  display-message) printf '%%1\n' ;;
  capture-pane) printf 'idle\n> \n' ;;
esac
SH
  for t in gh gh-axi curl; do
    cat > "$fb/$t" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$(basename "$0")" >> "${FM_FORGE_LOG:-/dev/null}"
exit 97
SH
  done
  chmod +x "$fb"/*
}

mk_repo() { # <dir> <branch>
  git -C "$(dirname "$1")" init -q "$(basename "$1")" 2>/dev/null || { mkdir -p "$1"; git -C "$1" init -q; }
  git -C "$1" -c user.name=fmtest -c user.email=fm@test.invalid commit -q --allow-empty -m init
  git -C "$1" checkout -q -b "$2"
}

stamp_min_ago() { local e=$(( $(date +%s) - $1 * 60 )); date -r "$e" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$e" '+%Y-%m-%d %H:%M'; }
backdate() { local e=$(( $(date +%s) - $2 * 60 )) s; s=$(date -r "$e" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$e" +%Y%m%d%H%M.%S); touch -t "$s" "$1"; }

run_failed_yaml() { # <branch> <head> [pr]
  printf 'run:\n  id: "01RUN"\n  branch: %s\n  status: completed\n  head: "%s"\n  pr: "%s"\n  findings: none\noutcome: failed\n' "$1" "$2" "${3:-}"
}

hdr() { printf '\n========== %s ==========\n' "$*"; }

# ---------------------------------------------------------------- scenario 1
hdr "S1 stale-failed-run-does-not-mask-a-declared-pause"
d=$W/s1; mkdir -p "$d/state"; mk_repo "$d/wt" fm/feat-pause; mk_fakebin "$d"
head=$(git -C "$d/wt" rev-parse HEAD)
printf 'window=fm:fm-feat\nworktree=%s\nkind=ship\n' "$d/wt" > "$d/state/feat.meta"
printf 'paused: polling the CI run myself\n' > "$d/state/feat.status"
echo "crew's own last word : $(cat "$d/state/feat.status")"
echo "axi status           : terminal run, outcome failed, head $head"
echo "ledger row           : failed fm/feat-pause f0f0f0f0 (a head this worktree does not carry)"
out=$(PATH="$d/fakebin:$PATH" FM_STATE_OVERRIDE="$d/state" \
  FM_FAKE_AXI_STATUS="$(run_failed_yaml fm/feat-pause "$head")" \
  FM_FAKE_RUNS_LIST="  failed     fm/feat-pause f0f0f0f0  $(stamp_min_ago 60)" \
  "$CREW_STATE" feat)
echo "fm-crew-state.sh feat: $out"

hdr "S1b same fixture against the pre-fix reader (base commit 9bc051f)"
basedir=$W/base; mkdir -p "$basedir"
git -C "$ROOT" archive 9bc051ff43c6e4d23c163ee8f1d87551a11050c0 bin | tar -x -C "$basedir"
outb=$(PATH="$d/fakebin:$PATH" FM_STATE_OVERRIDE="$d/state" \
  FM_FAKE_AXI_STATUS="$(run_failed_yaml fm/feat-pause "$head")" \
  FM_FAKE_RUNS_LIST="  failed     fm/feat-pause f0f0f0f0  $(stamp_min_ago 60)" \
  bash "$basedir/bin/fm-crew-state.sh" feat)
echo "pre-fix reader       : $outb"

# ---------------------------------------------------------------- scenario 2
hdr "S2 a-real-current-run-failure-still-reports-failed (adversarial)"
d=$W/s2; mkdir -p "$d/state"; mk_repo "$d/wt" fm/feat-midrun; mk_fakebin "$d"
head=$(git -C "$d/wt" rev-parse HEAD); short=$(git -C "$d/wt" rev-parse --short=8 HEAD)
printf 'window=fm:fm-feat\nworktree=%s\nkind=ship\n' "$d/wt" > "$d/state/feat.meta"
printf 'paused: polling the CI run myself\n' > "$d/state/feat.status"
backdate "$d/state/feat.status" 40
echo "crew's own last word : paused (written 40 min ago, DURING the run)"
echo "ledger row           : failed fm/feat-midrun $short started 60 min ago - this IS the attributed run"
out=$(PATH="$d/fakebin:$PATH" FM_STATE_OVERRIDE="$d/state" \
  FM_FAKE_AXI_STATUS="$(run_failed_yaml fm/feat-midrun "$head")" \
  FM_FAKE_RUNS_LIST="  failed     fm/feat-midrun ${short}  $(stamp_min_ago 60)" \
  "$CREW_STATE" feat)
echo "fm-crew-state.sh feat: $out"

# ---------------------------------------------------------------- scenario 3
hdr "S3 unbindable-live-replacement-reads-unknown-not-working"
d=$W/s3; mkdir -p "$d/state"; mk_repo "$d/wt" fm/feat-rerun; mk_fakebin "$d"
head=$(git -C "$d/wt" rev-parse HEAD); short=$(git -C "$d/wt" rev-parse --short=8 HEAD)
printf 'window=fm:fm-feat\nworktree=%s\nkind=ship\n' "$d/wt" > "$d/state/feat.meta"
echo "axi status           : terminal run, outcome failed"
echo "ledger row           : running fm/feat-rerun $short - a rerun that started between the two CLI reads"
out=$(PATH="$d/fakebin:$PATH" FM_STATE_OVERRIDE="$d/state" \
  FM_FAKE_AXI_STATUS="$(run_failed_yaml fm/feat-rerun "$head")" \
  FM_FAKE_RUNS_LIST="  running    fm/feat-rerun ${short}  $(stamp_min_ago 5)" \
  "$CREW_STATE" feat)
echo "fm-crew-state.sh feat: $out"

# ---------------------------------------------------------------- scenario 4
hdr "S4 failed-run-names-no-pull-request-it-never-opened"
d=$W/s4; mkdir -p "$d/state"; mk_repo "$d/wt" fm/feat-nopr; mk_fakebin "$d"
head=$(git -C "$d/wt" rev-parse HEAD); short=$(git -C "$d/wt" rev-parse --short=8 HEAD)
printf 'window=fm:fm-feat\nworktree=%s\nkind=ship\npr=https://example.test/owner/repo/pull/1\n' "$d/wt" > "$d/state/feat.meta"
echo "meta records         : pr=https://example.test/owner/repo/pull/1 (an OLDER record)"
echo "axi status           : terminal run, outcome failed, pr: \"\" - this run opened none"
out=$(PATH="$d/fakebin:$PATH" FM_STATE_OVERRIDE="$d/state" \
  FM_FAKE_AXI_STATUS="$(run_failed_yaml fm/feat-nopr "$head")" \
  FM_FAKE_RUNS_LIST="  failed     fm/feat-nopr ${short}  $(stamp_min_ago 60)" \
  "$CREW_STATE" feat)
echo "fm-crew-state.sh feat: $out"

# ---------------------------------------------------------------- scenario 5
hdr "S5 supervisor end-to-end: what the captain is actually told"
# Each case gets its own firstmate home so the scan-interval marker never
# throttles the next one. The REAL bin/fm-crew-state.sh is the state source -
# no FM_INACTIVE_CREW_STATE_BIN override.
run_passed_yaml() { # <branch> <head> <pr>
  printf 'run:\n  id: "01RUN"\n  branch: %s\n  status: completed\n  head: "%s"\n  pr: "%s"\n  findings: none\noutcome: passed\n' "$1" "$2" "$3"
}

e2e_case() { # <name> <status-line> <status-age-min> <ledger-head> [passed-pr]
  local name=$1 line=$2 age=$3 lhead=$4 pass_pr=${5:-} MAIN yaml ledger
  MAIN=$W/s5-$name/main
  mkdir -p "$MAIN"/{state,data,config,projects} "$W/s5-$name/root"
  mk_fakebin "$W/s5-$name"
  export FM_FORGE_LOG="$W/s5-$name/forge.log"; : > "$FM_FORGE_LOG"
  mk_repo "$MAIN/projects/child" fm/feat-e2e
  local head short; head=$(git -C "$MAIN/projects/child" rev-parse HEAD)
  short=$(git -C "$MAIN/projects/child" rev-parse --short=8 HEAD)
  [ "$lhead" = self ] && lhead=$short
  printf 'window=firstmate:fm-child\nworktree=%s\nproject=alpha\nharness=codex\nkind=ship\nmode=no-mistakes\nyolo=off\nspawn_gen=s1.1\npr=https://example.test/owner/repo/pull/1\n' \
    "$MAIN/projects/child" > "$MAIN/state/child.meta"
  printf '%s\n' "$line" > "$MAIN/state/child.status"
  : > "$MAIN/state/child.turn-ended"
  backdate "$MAIN/state/child.meta" 2; backdate "$MAIN/state/child.status" "$age"; backdate "$MAIN/state/child.turn-ended" 2
  if [ -n "$pass_pr" ]; then
    yaml=$(run_passed_yaml fm/feat-e2e "$head" "$pass_pr")
    ledger="  completed  fm/feat-e2e ${lhead}  $(stamp_min_ago 60)  $pass_pr"
  else
    yaml=$(run_failed_yaml fm/feat-e2e "$head")
    ledger="  failed     fm/feat-e2e ${lhead}  $(stamp_min_ago 60)"
  fi
  echo "crew's last word     : $line  (written $age min ago)"
  echo "ledger row           :$ledger"
  echo "meta records         : pr=https://example.test/owner/repo/pull/1"
  echo "reader says          : $(PATH="$W/s5-$name/fakebin:$PATH" FM_STATE_OVERRIDE="$MAIN/state" \
      FM_CREW_STATE_NO_FORGE=1 FM_FAKE_AXI_STATUS="$yaml" FM_FAKE_RUNS_LIST="$ledger" "$CREW_STATE" child)"
  PATH="$W/s5-$name/fakebin:$PATH" FM_ROOT_OVERRIDE="$W/s5-$name/root" FM_HOME="$MAIN" \
    FM_STATE_OVERRIDE="$MAIN/state" FM_DATA_OVERRIDE="$MAIN/data" FM_CONFIG_OVERRIDE="$MAIN/config" \
    FM_INACTIVE_RECONCILE_SECS=60 \
    FM_FAKE_AXI_STATUS="$yaml" FM_FAKE_RUNS_LIST="$ledger" \
    "$RECON" scan --startup 2>&1 | sed 's/^/captain is told   : /'
  echo "queued wake payload  : $(grep -o 'inactive-outcome:[^\"]*' "$MAIN/state/.wake-queue" 2>/dev/null | tail -1)"
  echo "forge/PR API calls   : $(wc -l < "$FM_FORGE_LOG" | tr -d ' ')"
  echo
}

echo "-- 5a: stale failed run (foreign head) + the crew's later declared pause"
e2e_case pause 'paused: polling the CI run myself' 1 f0f0f0f0
echo "-- 5b: the current run genuinely failed after a mid-run pause; crew silent"
e2e_case midrun 'paused: polling the CI run myself' 40 self
echo "-- 5c: routine ship shape: done written BEFORE the run, run then failed"
e2e_case routine 'done: implementation complete' 120 self
echo "-- 5d: the same failure with the crew still mid-sentence (no contradicting word)"
e2e_case uncontradicted 'working: still validating' 2 self
echo "-- 5e: a passed run that DID open a pull request"
e2e_case passed 'working: still validating' 2 self 'https://github.com/o/r/pull/3701'

# ---------------------------------------------------------------- scenario 6
hdr "S6 the same 5a fixture driven through the PRE-FIX supervisor (base 9bc051f)"
# Identical inputs to 5a - healthy work the crew paused, over a stale failed run
# the ledger cannot bind to this worktree - but the base-commit bin/ is used for
# BOTH the reader and the reconciler, so this is what the captain used to be told.
MAIN=$W/s6/main
mkdir -p "$MAIN"/{state,data,config,projects} "$W/s6/root"
mk_fakebin "$W/s6"
export FM_FORGE_LOG="$W/s6/forge.log"; : > "$FM_FORGE_LOG"
mk_repo "$MAIN/projects/child" fm/feat-e2e
head=$(git -C "$MAIN/projects/child" rev-parse HEAD)
printf 'window=firstmate:fm-child\nworktree=%s\nproject=alpha\nharness=codex\nkind=ship\nmode=no-mistakes\nyolo=off\nspawn_gen=s1.1\npr=https://example.test/owner/repo/pull/1\n' \
  "$MAIN/projects/child" > "$MAIN/state/child.meta"
printf 'paused: polling the CI run myself\n' > "$MAIN/state/child.status"
: > "$MAIN/state/child.turn-ended"
backdate "$MAIN/state/child.meta" 2; backdate "$MAIN/state/child.status" 1; backdate "$MAIN/state/child.turn-ended" 2
yaml=$(run_failed_yaml fm/feat-e2e "$head")
ledger="  failed     fm/feat-e2e f0f0f0f0  $(stamp_min_ago 60)"
echo "crew's last word     : paused: polling the CI run myself (1 min ago)"
echo "ledger row           :$ledger"
echo "meta records         : pr=https://example.test/owner/repo/pull/1"
echo "pre-fix reader says  : $(PATH="$W/s6/fakebin:$PATH" FM_STATE_OVERRIDE="$MAIN/state" \
    FM_FAKE_AXI_STATUS="$yaml" FM_FAKE_RUNS_LIST="$ledger" bash "$W/base/bin/fm-crew-state.sh" child)"
PATH="$W/s6/fakebin:$PATH" FM_ROOT_OVERRIDE="$W/s6/root" FM_HOME="$MAIN" \
  FM_STATE_OVERRIDE="$MAIN/state" FM_DATA_OVERRIDE="$MAIN/data" FM_CONFIG_OVERRIDE="$MAIN/config" \
  FM_INACTIVE_RECONCILE_SECS=60 FM_FAKE_AXI_STATUS="$yaml" FM_FAKE_RUNS_LIST="$ledger" \
  bash "$W/base/bin/fm-inactive-reconcile.sh" scan --startup 2>&1 | sed 's/^/captain WAS told  : /'
echo "queued wake payload  : $(grep -o 'inactive-outcome:[^"]*' "$MAIN/state/.wake-queue" 2>/dev/null | tail -1)"

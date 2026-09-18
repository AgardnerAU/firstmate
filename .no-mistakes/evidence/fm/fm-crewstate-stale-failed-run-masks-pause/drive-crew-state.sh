#!/usr/bin/env bash
# Manual end-user drive of bin/fm-crew-state.sh: real throwaway git worktrees,
# a fake `no-mistakes` CLI serving the run record / ledger the reader queries,
# and the real helper invoked exactly as firstmate invokes it each heartbeat.
set -u
ROOT=${ROOT:-$PWD}
CREW_STATE="$ROOT/bin/fm-crew-state.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-crew-state-drive.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=fmtest GIT_AUTHOR_EMAIL=fmtest@example.invalid
export GIT_COMMITTER_NAME=fmtest GIT_COMMITTER_EMAIL=fmtest@example.invalid

FB="$TMP/fakebin"; mkdir -p "$FB"
cat > "$FB/no-mistakes" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  axi)
    shift
    if [ "$#" = 0 ]; then printf '%s\n' "${FM_FAKE_AXI_HOME:-${FM_FAKE_AXI_STATUS:-}}"; exit 0; fi
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
cat > "$FB/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  display-message) printf '%%1\n' ;;
  capture-pane) printf 'all quiet\n> \n' ;;
esac
exit 0
SH
chmod +x "$FB/no-mistakes" "$FB/tmux"

stamp_minutes_ago() { local e; e=$(( $(date +%s) - $1 * 60 )); date -r "$e" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$e" '+%Y-%m-%d %H:%M'; }

setup() {  # <case> <branch> -> sets WT SHORT D
  D="$TMP/$1"; mkdir -p "$D/state"
  WT="$D/wt"; mkdir -p "$WT"
  git -C "$WT" init -q
  git -C "$WT" commit -q --allow-empty -m init
  git -C "$WT" checkout -q -b "$2"
  HEAD_SHA=$(git -C "$WT" rev-parse HEAD)
  SHORT=$(git -C "$WT" rev-parse --short=8 HEAD)
  printf 'window=fm:fm-%s\nworktree=%s\nkind=ship\n' "$1" "$WT" > "$D/state/$1.meta"
}
drive() { PATH="$FB:$PATH" FM_STATE_OVERRIDE="$D/state" "$CREW_STATE" "$1"; }
hdr() { printf '\n================================================================\nSCENARIO: %s\n----------------------------------------------------------------\n' "$1"; }
show() { printf 'crew says (state/<id>.status): %s\n' "${1:-<no status log>}"; }

# ---------------------------------------------------------------- S1
hdr "S1 stale failed run, newer live run in flight on the branch"
setup s1 fm/feat-s1
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-s1
  status: failed
  head: \"$HEAD_SHA\"
  pr: \"https://github.com/o/r/pull/1\"
  findings: none
outcome: failed"
export FM_FAKE_RUNS_LIST="  running    fm/feat-s1 f0f0f0f0  $(stamp_minutes_ago 10)
  failed     fm/feat-s1 ${SHORT}  $(stamp_minutes_ago 90)"
printf 'no-mistakes axi status  -> failed run at this head, pr https://github.com/o/r/pull/1\n'
printf 'no-mistakes runs        ->\n%s\n\nfm-crew-state.sh feat-s1 ->\n  ' "$FM_FAKE_RUNS_LIST"
drive s1

# ---------------------------------------------------------------- S2
hdr "S2 genuine failure, nothing newer on the branch (adversarial: guard must not hide it)"
setup s2 fm/feat-s2
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-s2
  status: failed
  head: \"$HEAD_SHA\"
  pr: \"\"
  findings: none
outcome: failed"
export FM_FAKE_RUNS_LIST="  failed     fm/feat-s2 ${SHORT}  $(stamp_minutes_ago 90)"
printf 'no-mistakes runs        ->\n%s\n\nfm-crew-state.sh feat-s2 ->\n  ' "$FM_FAKE_RUNS_LIST"
drive s2

# ---------------------------------------------------------------- S3
hdr "S3 rerun at the same head: the newest row's PR is published, not the stale one"
setup s3 fm/feat-s3
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-s3
  status: failed
  head: \"$HEAD_SHA\"
  pr: \"https://github.com/o/r/pull/1111\"
  findings: none
outcome: failed"
export FM_FAKE_RUNS_LIST="  failed     fm/feat-s3 ${SHORT}  $(stamp_minutes_ago 30)  https://github.com/o/r/pull/2222
  failed     fm/feat-s3 ${SHORT}  $(stamp_minutes_ago 90)  https://github.com/o/r/pull/1111"
printf 'attributed run pr: pull/1111 ; newest ledger row pr: pull/2222\n\nfm-crew-state.sh feat-s3 ->\n  '
drive s3

# ---------------------------------------------------------------- S4
hdr "S4 delivered PR with NO ledger row at all (long-inactive crew, run outside the listing window)"
setup s4 fm/feat-s4
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-s4
  status: completed
  head: \"$HEAD_SHA\"
  pr: \"https://github.com/o/r/pull/4444\"
  findings: none
outcome: passed"
export FM_FAKE_RUNS_LIST=""
printf 'no-mistakes runs        -> <empty: branch has no row in the window>\n\nfm-crew-state.sh feat-s4 ->\n  '
FM_CREW_STATE_NO_FORGE=1 drive s4

# ---------------------------------------------------------------- S5
hdr "S5 line shape: the run id is the last FIELD, the verdict is one sentence"
setup s5 fm/feat-s5
export FM_FAKE_AXI_HOME="count: 1 of 1 total
runs[1]{id,branch,status,head,pr}:
  01RUN,fm/feat-s5,failed,${HEAD_SHA},\"\""
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-s5
  status: failed
  head: \"$HEAD_SHA\"
  pr: \"\"
  findings: none
outcome: failed"
export FM_FAKE_AXI_STATUS_RUN="$FM_FAKE_AXI_STATUS"
export FM_FAKE_RUNS_LIST="  failed     fm/feat-s5 f0f0f0f0  $(stamp_minutes_ago 30)"
printf 'fm-crew-state.sh feat-s5 ->\n  '
drive s5
unset FM_FAKE_AXI_HOME FM_FAKE_AXI_STATUS_RUN

# ---------------------------------------------------------------- S6
hdr "S6 coarse ledger path: one row must not be reported as superseding itself"
setup s6 fm/feat-s6
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/other-crew
  status: running
  head: \"aaaaaaa\"
  pr: \"\"
  findings: none
  steps[2]{step,status,findings,duration_ms}:
    intent,completed,0,0
    review,running,0,0"
export FM_FAKE_RUNS_LIST="  running    fm/other-crew aaaaaaa  $(stamp_minutes_ago 10)
  cancelled  fm/feat-s6 ${SHORT}  $(stamp_minutes_ago 30)  https://github.com/o/r/pull/3333"
printf 'axi status answers ANOTHER crew, so this crew falls to the coarse ledger read\n\nfm-crew-state.sh feat-s6 ->\n  '
drive s6

# ---------------------------------------------------------------- S7
hdr "S7 adversarial: daemon socket refused in the log outranks the ledger's terminal row"
setup s7 fm/feat-s7
printf 'blocked: cannot reach the no-mistakes daemon: connection refused on the control socket\n' > "$D/state/s7.status"
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-s7
  status: failed
  head: \"$HEAD_SHA\"
  pr: \"\"
  findings: none
outcome: failed"
export FM_FAKE_RUNS_LIST="  failed     fm/feat-s7 ${SHORT}  $(stamp_minutes_ago 30)"
show "$(cat "$D/state/s7.status")"
printf '\nfm-crew-state.sh feat-s7 ->\n  '
drive s7

printf '\n'

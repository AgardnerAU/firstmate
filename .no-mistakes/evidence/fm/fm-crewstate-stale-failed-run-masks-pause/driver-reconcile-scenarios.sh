set -u
. /tmp/nm-drive/harness.sh
mk_fakebin
export FM_FAKE_AXI_STATUS FM_FAKE_RUNS_LIST
hdr() { printf '\n===== %s =====\n' "$*"; }
show() {
  printf 'wake queue:\n'; sed -n 's/^/  /p' "$W/home/state/.wake-queue" 2>/dev/null || printf '  (empty)\n'
  printf 'terminal outcome records:\n'
  local f found=0
  for f in "$W/home/state/terminal-outcomes"/*; do
    [ -e "$f" ] || continue; found=1
    printf '  --- %s\n' "${f##*/}"; sed -n 's/^/    /p' "$f"
  done
  [ "$found" = 1 ] || printf '  (none)\n'
}
arm() { # <id>
  : > "$W/home/state/$1.turn-ended"
  age_files "$W/home/state/$1.meta" "$W/home/state/$1.status" "$W/home/state/$1.turn-ended"
}

case "${CASE:?}" in
R1)
  hdr "R1 crew wrote 'done:' mid-run, the run then failed, crew silent"
  new_crew child fm/feat-r1
  printf 'done: implementation complete\n' > "$W/home/state/child.status"; arm child
  FM_FAKE_AXI_STATUS="$(run_failed_with_pr fm/feat-r1 https://github.com/o/r/pull/7)"
  FM_FAKE_RUNS_LIST="$(printf '  failed     fm/feat-r1 %s  %s  https://github.com/o/r/pull/7\n' "$HEAD_SHORT" "$(stamp_ago 30)")"
  printf 'status log: %s' "$(cat "$W/home/state/child.status")"
  printf 'meta pr= (the crew task record): %s\n' "$(sed -n 's/^pr=//p' "$W/home/state/child.meta")"
  printf 'reader says: '; crew_state child
  reconcile; show ;;
R2)
  hdr "R2 healthy progressing work: stale failed run, newer completed run on the branch"
  new_crew child fm/feat-r2
  printf 'paused: waiting on the pipeline\n' > "$W/home/state/child.status"; arm child
  FM_FAKE_AXI_STATUS="$(run_failed_with_pr fm/feat-r2 https://github.com/o/r/pull/1)"
  FM_FAKE_RUNS_LIST="$(printf '  completed  fm/feat-r2 f0f0f0f0  %s  https://github.com/o/r/pull/2890\n  failed     fm/feat-r2 %s  %s  https://github.com/o/r/pull/1\n' "$(stamp_ago 30)" "$HEAD_SHORT" "$(stamp_ago 90)")"
  printf 'reader says: '; crew_state child
  reconcile; show ;;
R3)
  hdr "R3 scout whose last line takes the PR ready-signal shape"
  new_crew child fm/feat-r3 scout
  sed -i.bak 's/^harness=codex/harness=claude/' "$W/home/state/child.meta"; rm -f "$W/home/state/child.meta.bak"
  printf 'done: PR https://example.test/o/r/pull/7 checks green\n' > "$W/home/state/child.status"
  gen=$(FM_STATE_OVERRIDE="$W/home/state" "$SRC/bin/fm-busy-event.sh" arm "$W/home/state" child)
  FM_STATE_OVERRIDE="$W/home/state" "$SRC/bin/fm-busy-event.sh" apply "$W/home/state" child idle --gen "$gen" --source claude-hook --event stop >/dev/null
  arm child
  printf 'status log: %s' "$(cat "$W/home/state/child.status")"
  printf 'reader says: '; crew_state child
  reconcile; show ;;
esac

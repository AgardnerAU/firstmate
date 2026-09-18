set -u
. /tmp/nm-drive/harness.sh
mk_fakebin
export FM_FAKE_AXI_STATUS FM_FAKE_RUNS_LIST

hdr() { printf '\n===== %s =====\n' "$*"; }

# S1 stale failed run + newer live run on the branch
hdr "S1 stale failed run (pr=pull/1) superseded by a newer live run"
new_crew feat-a fm/feat-a
FM_FAKE_AXI_STATUS="$(run_failed_with_pr fm/feat-a https://github.com/o/r/pull/1)"
FM_FAKE_RUNS_LIST="$(printf '  running    fm/feat-a f0f0f0f0  %s\n  failed     fm/feat-a %s  %s\n' "$(stamp_ago 20)" "$HEAD_SHORT" "$(stamp_ago 90)")"
printf 'ledger:\n%s\n' "$FM_FAKE_RUNS_LIST"
printf 'crew-state: '; crew_state feat-a

# S2 stale failed run + newer COMPLETED row carrying the real PR
hdr "S2 stale failed run (pr=pull/1) with a newer completed row (pr=pull/2890)"
new_crew feat-b fm/feat-b
printf 'paused: waiting on the pipeline\n' > "$W/home/state/feat-b.status"
FM_FAKE_AXI_STATUS="$(run_failed_with_pr fm/feat-b https://github.com/o/r/pull/1)"
FM_FAKE_RUNS_LIST="$(printf '  completed  fm/feat-b f0f0f0f0  %s  https://github.com/o/r/pull/2890\n  failed     fm/feat-b %s  %s  https://github.com/o/r/pull/1\n' "$(stamp_ago 30)" "$HEAD_SHORT" "$(stamp_ago 90)")"
printf 'status log: %s' "$(cat "$W/home/state/feat-b.status")"
printf 'ledger:\n%s\n' "$FM_FAKE_RUNS_LIST"
printf 'crew-state: '; crew_state feat-b

# S3 adversarial: genuine current failure, nothing newer -> must still read failed
hdr "S3 genuine current failure, crew silent, ledger agrees"
new_crew feat-c fm/feat-c
FM_FAKE_AXI_STATUS="$(run_failed_with_pr fm/feat-c https://github.com/o/r/pull/7)"
FM_FAKE_RUNS_LIST="$(printf '  failed     fm/feat-c %s  %s  https://github.com/o/r/pull/7\n' "$HEAD_SHORT" "$(stamp_ago 30)")"
printf 'ledger:\n%s\n' "$FM_FAKE_RUNS_LIST"
printf 'crew-state: '; crew_state feat-c

# S4 adversarial: mid-run `paused:` line must not mask the current run's failure
hdr "S4 mid-run pause line over a current failed run"
new_crew feat-d fm/feat-d
printf 'paused: waiting on a human answer\n' > "$W/home/state/feat-d.status"
age_files "$W/home/state/feat-d.status"
FM_FAKE_AXI_STATUS="$(run_failed_with_pr fm/feat-d https://github.com/o/r/pull/9)"
FM_FAKE_RUNS_LIST="$(printf '  failed     fm/feat-d %s  %s  https://github.com/o/r/pull/9\n' "$HEAD_SHORT" "$(stamp_ago 30)")"
printf 'status log: %s' "$(cat "$W/home/state/feat-d.status")"
printf 'crew-state: '; crew_state feat-d

# S5 adversarial: a live socket-refusal blocked line outranks the stale-failure rules
hdr "S5 daemon socket refused, blocked line, over a ledger-resolved terminal failure"
new_crew feat-e fm/feat-e
printf 'blocked: no-mistakes daemon socket refused connections\n' > "$W/home/state/feat-e.status"
FM_FAKE_AXI_STATUS="$(printf 'run:\n  id: "01OTHER"\n  branch: fm/other-crew\n  status: running\n  head: "f0f0f0f0"\n  pr: ""\n  findings: none\n')"
FM_FAKE_RUNS_LIST="$(printf '  failed     fm/feat-e %s  %s  https://github.com/o/r/pull/3\n' "$HEAD_SHORT" "$(stamp_ago 60)")"
printf 'status log: %s' "$(cat "$W/home/state/feat-e.status")"
printf 'ledger:\n%s\n' "$FM_FAKE_RUNS_LIST"
printf 'crew-state: '; crew_state feat-e

# S6 coarse path: the attributed run belongs to another branch, so the reading IS the ledger row
hdr "S6 coarse ledger reading must not claim it superseded itself"
new_crew feat-f fm/feat-f
FM_FAKE_AXI_STATUS="$(run_failed_with_pr fm/other-branch https://github.com/o/r/pull/5)"
FM_FAKE_RUNS_LIST="$(printf '  cancelled  fm/feat-f %s  %s  https://github.com/o/r/pull/11\n' "$HEAD_SHORT" "$(stamp_ago 20)")"
printf 'ledger:\n%s\n' "$FM_FAKE_RUNS_LIST"
printf 'crew-state: '; crew_state feat-f

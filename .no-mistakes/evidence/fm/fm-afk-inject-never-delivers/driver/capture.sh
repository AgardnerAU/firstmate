#!/usr/bin/env bash
set -u
E=/Users/agardner/.no-mistakes/evidence/01M2TFX5VSAFZ4MQ5XA9N5JBFN
W=/Users/agardner/.no-mistakes/worktrees/c272d8f3fc4c/01M2TFX5VSAFZ4MQ5XA9N5JBFN
BT=$(mktemp -d "${TMPDIR:-/tmp}/fm-base.XXXXXX"); (cd "$W" && git archive 9bc051f) | tar -x -C "$BT"
IT=$(mktemp -d "${TMPDIR:-/tmp}/fm-mid.XXXXXX");  (cd "$W" && git archive 83c4296) | tar -x -C "$IT"
echo "Away-mode self-hosted escalation delivery - the real daemon driven over the real herdr adapter."
echo "The only substitute is the external herdr 0.8.0 CLI, replaced by a herdr-shaped fake pane"
echo "(driver/fake-herdr): a composer buffer, a transcript, a native agent-state pinned 'working' by"
echo "the daemon's own background job, and an optional swallowed Enter. No firstmate code is mocked."
echo
echo "--- native agent-state reader (bin/backends/herdr.sh) ---"
bash "$E/driver/probe.sh" "$BT" "BASE 9bc051f (before the fix)" | grep -v '^state dir'
bash "$E/driver/probe.sh" "$W" "BRANCH 0752911" | grep -v '^state dir'
echo
echo "--- away-mode daemon (bin/fm-supervise-daemon.sh) ---"
echo "S3 = escalation raised while away, self-hosted, harness turn finished (must DELIVER)"
echo "S4 = same, but the harness really is mid-turn                         (must DEFER)"
echo "S5 = same, every Enter swallowed                                      (must keep buffer + wedge marker)"
echo
bash "$E/driver/run.sh" "$BT" "BASE 9bc051f (before the fix)"
bash "$E/driver/run.sh" "$IT" "INTERMEDIATE 83c4296 (busy-guard fix only)"
bash "$E/driver/run.sh" "$W"  "BRANCH 0752911 (both fixes)"
rm -rf "$BT" "$IT"

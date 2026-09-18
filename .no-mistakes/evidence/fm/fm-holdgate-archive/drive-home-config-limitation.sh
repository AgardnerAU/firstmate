#!/usr/bin/env bash
# The tip commit documents a limitation: a home-level [markdown] archive in
# ~/.tasks-axi/config.toml is NOT honoured by the gate, so such a home still
# resolves against the default path. Drive it with HOME pointed at a fixture.
set -u
ROOT=/Users/agardner/.no-mistakes/worktrees/c272d8f3fc4c/01M2TNESBHX3ZAAWT5WJZM3YVY
HOLD="$ROOT/bin/fm-captain-hold.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/homecfg.XXXXXX")
TASKS_AXI_BIN=$(command -v tasks-axi)
h="$TMP/home"; mkdir -p "$h/data" "$h/state" "$h/config" "$h/projects" "$h/fakebin" "$TMP/fakehome/.tasks-axi"
# project config: [markdown] with NO archive key
printf '[markdown]\npath = "data/backlog.md"\n' > "$h/.tasks.toml"
# home-level config: sets the archive somewhere else
printf '[markdown]\narchive = "data/home-closed.md"\n' > "$TMP/fakehome/.tasks-axi/config.toml"
printf '## In flight\n\n## Queued\n\n## Done\n' > "$h/data/backlog.md"
for b in tmux treehouse no-mistakes gh gh-axi; do printf '#!/bin/sh\nexit 0\n' > "$h/fakebin/$b"; chmod +x "$h/fakebin/$b"; done
mkdir -p "$h/data/sample-homecfg-review"
run() { PATH="$h/fakebin:$PATH" REAL_TASKS_AXI="$TASKS_AXI_BIN" HOME="$TMP/fakehome" FM_HOME="$h" \
  FM_STATE_OVERRIDE="$h/state" FM_DATA_OVERRIDE="$h/data" FM_CONFIG_OVERRIDE="$h/config" "$@"; }
captain() { run "$HOLD" "$@"; }
(cd "$h" && HOME="$TMP/fakehome" tasks-axi add sample-homecfg-review "Review" --kind scout --repo sample --start >/dev/null)
printf 'window=firstmate:fm-x\nworktree=%s/projects/missing\nproject=%s/projects/sample\nharness=codex\nkind=scout\nmode=scout\nspawn_gen=fx\n' "$h" "$h" > "$h/state/sample-homecfg-review.meta"
printf 'done: report complete\n' > "$h/state/sample-homecfg-review.status"
printf '# r\n\ntext\n' > "$h/data/sample-homecfg-review/report.md"
captain hold sample-homecfg-call --title "Choose" --reason "pending" --repo sample >/dev/null
captain complete sample-homecfg-review sample-homecfg-call >/dev/null
printf 'Northern route.\n' > "$h/a.txt"
captain answer sample-homecfg-call --decision-file "$h/a.txt" >/dev/null
echo "\$ HOME=<fixture> tasks-axi prune --keep 0 --state done"
(cd "$h" && HOME="$TMP/fakehome" tasks-axi prune --keep 0 --state "done")
echo "files written under data/:"; ls "$h/data"
echo "\$ fm-captain-hold.sh verify sample-homecfg-review"
captain verify sample-homecfg-review; echo "exit=$?"

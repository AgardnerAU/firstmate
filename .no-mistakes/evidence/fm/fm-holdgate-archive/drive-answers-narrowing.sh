#!/usr/bin/env bash
# `answers` must stay on the live backlog: an id whose only row is an archived
# answered one is skipped as absent, with no parent-channel write, exactly as it
# was before this branch.
set -u
ROOT=${ROOT_OVERRIDE:-/Users/agardner/.no-mistakes/worktrees/c272d8f3fc4c/01M2TNESBHX3ZAAWT5WJZM3YVY}
HOLD="$ROOT/bin/fm-captain-hold.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/answersnarrow.XXXXXX")
TASKS_AXI_BIN=$(command -v tasks-axi)
h="$TMP/home"; mkdir -p "$h/data" "$h/state" "$h/config" "$h/projects" "$h/fakebin"
cp "$ROOT/.tasks.toml" "$h/.tasks.toml"
printf '## In flight\n\n## Queued\n\n## Done\n' > "$h/data/backlog.md"
for b in tmux treehouse no-mistakes gh gh-axi; do printf '#!/bin/sh\nexit 0\n' > "$h/fakebin/$b"; chmod +x "$h/fakebin/$b"; done
captain() { PATH="$h/fakebin:$PATH" REAL_TASKS_AXI="$TASKS_AXI_BIN" FM_HOME="$h" \
  FM_STATE_OVERRIDE="$h/state" FM_DATA_OVERRIDE="$h/data" FM_CONFIG_OVERRIDE="$h/config" "$HOLD" "$@"; }
captain hold sample-answers-call --title "Choose" --reason "pending" --repo sample >/dev/null
printf 'Northern route.\n' > "$h/a.txt"
captain answer sample-answers-call --decision-file "$h/a.txt" >/dev/null
(cd "$h" && tasks-axi prune --keep 0 --state "done" >/dev/null)
echo "live backlog still carries the id? $( (cd "$h" && tasks-axi show sample-answers-call >/dev/null 2>&1) && echo yes || echo no )"
echo "archived? $(grep -c sample-answers-call "$h/data/done-archive.md")"
printf '\$ printf "sample-answers-call\\tNorthern route.\\n" | fm-captain-hold.sh answers --any-origin --source chat\n'
printf 'sample-answers-call\tNorthern route.\n' | captain answers --any-origin --source chat; echo "exit=$?"

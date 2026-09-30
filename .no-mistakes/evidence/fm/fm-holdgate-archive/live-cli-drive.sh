#!/usr/bin/env bash
# Drives bin/fm-captain-hold.sh with the real tasks-axi in a disposable home.
# Usage: live-cli-drive.sh <repo-root> <disposable-home>
set -u
R=$1 H=$2
REAL=$(command -v tasks-axi)
mkdir -p "$H/data" "$H/state" "$H/config" "$H/projects" "$H/fakebin"
cp "$R/.tasks.toml" "$H/"
printf '## In flight\n\n## Queued\n\n## Done\n' > "$H/data/backlog.md"
for b in tmux treehouse no-mistakes gh gh-axi; do printf '#!/bin/sh\nexit 0\n' > "$H/fakebin/$b"; chmod +x "$H/fakebin/$b"; done
cap() { echo "\$ fm-captain-hold.sh $*"; PATH="$H/fakebin:$PATH" REAL_TASKS_AXI="$REAL" FM_HOME="$H" FM_STATE_OVERRIDE="$H/state" FM_DATA_OVERRIDE="$H/data" FM_CONFIG_OVERRIDE="$H/config" "$R/bin/fm-captain-hold.sh" "$@"; echo "[exit $?]"; }
tk() { echo "\$ tasks-axi $*"; (cd "$H" && "$REAL" "$@") >/dev/null 2>&1; echo "[exit $?]"; }
meta() {
  printf 'window=firstmate:fm-%s\nworktree=%s/projects/missing-%s\nproject=%s/projects/sample\nharness=codex\nkind=scout\nmode=scout\nspawn_gen=fixture-%s\n' "$1" "$H" "$1" "$H" "$1" > "$H/state/$1.meta"
  printf 'done: report complete\n' > "$H/state/$1.status"
  mkdir -p "$H/data/$1"; printf '# report\n' > "$H/data/$1/report.md"
}
echo "## Scenario A setup: captain call held, inventoried, answered"
tk add live-origin "Origin" --kind scout --repo sample --start; meta live-origin
cap hold live-call --title "Pick a route" --reason "captain choice" --repo sample
cap complete live-origin live-call
echo "Take the north route." > "$H/ans.txt"
cap answer live-call --decision-file "$H/ans.txt"
echo
echo "## Scenario B setup: captain call held, inventoried, closed with no answer"
tk add drop-origin "Origin2" --kind scout --repo sample --start; meta drop-origin
cap hold drop-call --title "Pick another" --reason "captain choice" --repo sample
cap complete drop-origin drop-call
tk done drop-call
echo
echo "## Prune both closed calls into the archive"
tk prune --keep 0 --state done
echo "--- live backlog rows naming the calls: $(grep -c 'live-call\|drop-call' "$H/data/backlog.md")"
echo "--- archive rows:"; grep -E 'live-call|drop-call' "$H/data/done-archive.md" | cut -c1-110
echo
echo "## Scenario A: answered, archived call passes verify and complete"
cap verify live-origin
cap complete live-origin live-call
echo
echo "## Scenario B: archived call closed with no answer still fails"
cap verify drop-origin
echo
echo "## Scenario C: unreadable archive stops the gate by name"
chmod 000 "$H/data/done-archive.md"; cap verify live-origin; chmod 644 "$H/data/done-archive.md"
echo
echo "## Scenario D: erroring backlog backend stops the gate by name (no archive fallback)"
REALBIN="$REAL"
cat > "$H/fakebin/tasks-axi" <<SH
#!/usr/bin/env bash
archive=0
for arg in "\$@"; do case "\$arg" in */fm-captain-hold-archive.*) archive=1 ;; esac; done
if [ "\${1:-}" = show ] && [ "\${2:-}" = live-call ] && [ "\$archive" = 0 ]; then
  echo "simulated live backlog read failure" >&2; exit 91
fi
exec "$REALBIN" "\$@"
SH
chmod +x "$H/fakebin/tasks-axi"
cap verify live-origin

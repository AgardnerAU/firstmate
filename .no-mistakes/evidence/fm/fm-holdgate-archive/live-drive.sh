#!/usr/bin/env bash
# Live CLI drive of bin/fm-captain-hold.sh against a throwaway markdown home.
# Usage: live-drive.sh <repo-root-whose-bin-to-drive> <label>
set -u
ROOT=$1 LABEL=$2
HOME_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fm-live-$LABEL.XXXX")
mkdir -p "$HOME_DIR"/{data,state,config,projects,fakebin}
cp "$ROOT/.tasks.toml" "$HOME_DIR/.tasks.toml"
printf '## In flight\n\n## Queued\n\n## Done\n' > "$HOME_DIR/data/backlog.md"
for b in tmux treehouse no-mistakes gh gh-axi; do printf '#!/bin/sh\nexit 0\n' > "$HOME_DIR/fakebin/$b"; chmod +x "$HOME_DIR/fakebin/$b"; done
T=$(command -v tasks-axi)

say() { printf '\n$ %s\n' "$*"; }
cap() {
  say "fm-captain-hold.sh $*"
  PATH="$HOME_DIR/fakebin:$PATH" REAL_TASKS_AXI="$T" FM_HOME="$HOME_DIR" \
    FM_STATE_OVERRIDE="$HOME_DIR/state" FM_DATA_OVERRIDE="$HOME_DIR/data" \
    FM_CONFIG_OVERRIDE="$HOME_DIR/config" "$ROOT/bin/fm-captain-hold.sh" "$@" 2>&1
  echo "[exit $?]"
}
tx() { say "tasks-axi $*"; (cd "$HOME_DIR" && tasks-axi "$@" 2>&1) | head -6; }
origin() {
  mkdir -p "$HOME_DIR/data/$1"
  (cd "$HOME_DIR" && tasks-axi add "$1" "Investigate $1" --kind scout --repo sample --start >/dev/null)
  printf '%s\n' "window=firstmate:fm-$1" "worktree=$HOME_DIR/projects/missing-$1" \
    "project=$HOME_DIR/projects/sample" harness=codex kind=scout mode=scout "spawn_gen=live-$1" \
    > "$HOME_DIR/state/$1.meta"
  printf 'done: report complete\n' > "$HOME_DIR/state/$1.status"
}

echo "=== [$LABEL] tasks-axi $(tasks-axi --version), home $HOME_DIR"

echo; echo "### S1: answered captain call, then pruned to the archive"
origin north-review
cap hold north-call --title "Choose north or south" --reason "captain choice pending" --repo sample
cap complete north-review north-call
printf 'Take the northern route.\n' > "$HOME_DIR/answer.txt"
cap answer north-call --decision-file "$HOME_DIR/answer.txt"
tx prune --keep 0 --state done
tx show north-call
say "grep -c north-call data/done-archive.md"; grep -c north-call "$HOME_DIR/data/done-archive.md"
cap verify north-review
cap complete north-review north-call

echo; echo "### S2: call closed WITHOUT a captain answer, then pruned"
origin dropped-review
cap hold dropped-call --title "Choose the dropped option" --reason "captain choice pending" --repo sample
cap complete dropped-review dropped-call
tx done dropped-call
tx prune --keep 0 --state done
cap verify dropped-review

echo; echo "### S3: reused id - old answered row archived, newer unanswered row archived later"
origin reuse-review-1
cap hold reuse-call --title "First use of the id" --reason "pending" --repo sample
cap complete reuse-review-1 reuse-call
cap answer reuse-call --decision-file "$HOME_DIR/answer.txt"
tx prune --keep 0 --state done
origin reuse-review-2
cap hold reuse-call --title "Second use of the id" --reason "pending" --repo sample
cap complete reuse-review-2 reuse-call
tx done reuse-call
tx prune --keep 0 --state done
say "grep -c '^## Archived' data/done-archive.md"; grep -c '^## Archived' "$HOME_DIR/data/done-archive.md"
cap verify reuse-review-2

echo; echo "### S4: unreadable archive refuses by name"
chmod 000 "$HOME_DIR/data/done-archive.md"
cap verify north-review
chmod 644 "$HOME_DIR/data/done-archive.md"

echo; echo "### S5: live legacy call precedes archived exact-key history"
origin legacy-review
# archived exact id 'route' answered long ago
cap hold route --title "Old route call" --reason "pending" --repo sample
cap answer route --decision-file "$HOME_DIR/answer.txt"
tx prune --keep 0 --state done
# pre-collapse legacy identity for the same key, live and unanswered
cap hold legacy-review-decision-route --title "Legacy route call" --reason "pending" --repo sample
cap complete legacy-review route
tx done legacy-review-decision-route
cap verify legacy-review
tx prune --keep 0 --state done
cap verify legacy-review

rm -rf "$HOME_DIR"

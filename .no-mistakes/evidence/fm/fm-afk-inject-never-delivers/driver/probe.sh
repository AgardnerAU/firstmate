#!/usr/bin/env bash
# probe.sh <tree-root> <label>
set -u
ROOT=$1; LABEL=$2
D=$(mktemp -d "${TMPDIR:-/tmp}/fm-selfhost.XXXXXX")
export FAKE_HERDR_STATE="$D/pane"
mkdir -p "$FAKE_HERDR_STATE"
: > "$FAKE_HERDR_STATE/buffer"; : > "$FAKE_HERDR_STATE/submitted.log"; : > "$FAKE_HERDR_STATE/cli.log"
printf 'working\n' > "$FAKE_HERDR_STATE/agent_status"
printf '%s\n' '  crew c1: pushed the branch' '* Churned for 2m 17s' > "$FAKE_HERDR_STATE/transcript"
: > "$FAKE_HERDR_STATE/footer"
BIN=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$D/fakebin"; cp "$BIN/fake-herdr" "$D/fakebin/herdr"
export PATH="$D/fakebin:$PATH"
export HERDR_ENV=1 HERDR_PANE_ID=w1:p2 HERDR_SESSION=default
echo "### tree: $LABEL"
bash -c '
  . "$0/bin/backends/herdr.sh"
  printf "agent_status_raw(own pane)      = %s\n" "$(fm_backend_herdr_agent_status_raw default w1:p2)"
  printf "busy_state(own pane)            = %s\n" "$(fm_backend_herdr_busy_state default:w1:p2)"
  printf "busy_state(a worker pane w4:p1) = %s\n" "$(fm_backend_herdr_busy_state default:w4:p1)"
  printf "composer_state(own pane)        = %s\n" "$(fm_backend_herdr_composer_state default:w1:p2)"
' "$ROOT"
echo "state dir: $D"

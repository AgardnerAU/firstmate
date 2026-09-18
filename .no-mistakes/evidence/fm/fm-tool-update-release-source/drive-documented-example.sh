#!/usr/bin/env bash
# Fourth live pass: the documented starting point, docs/examples/watched-tools.json,
# is copied into a home exactly as the documentation tells an operator to, then
# armed and swept. Only the three published entries are kept, so the sweep asks
# the real npm registry and GitHub for herdr, tasks-axi and gnhf.
set -u
W=/Users/agardner/.no-mistakes/worktrees/c272d8f3fc4c/01M2TDFZN9WFMBX2HPJ48ZPHP0
CHECK="$W/bin/fm-tool-update-check.sh"
H=$(mktemp -d /tmp/fm-live-XXXXXX)
mkdir -p "$H/state" "$H/config"
echo "home=$H"
jq '{tools: [.tools[] | select(.published)]}' "$W/docs/examples/watched-tools.json" > "$H/config/watched-tools.json"
echo
echo "--- registry under test:"
cat "$H/config/watched-tools.json"
echo
echo "=== S12: arm the documented example ==="
env FM_HOME="$H" "$CHECK" arm; printf '[arm exit %s]\n' "$?"
echo
echo "=== S12: sweep it against the real release sources ==="
env FM_HOME="$H" FM_CHECK_TIMEOUT=30 FM_TOOL_UPDATE_INTERVAL=0 FM_TOOL_UPDATE_BUDGET_SECS=25 "$CHECK" check
printf '[check exit %s]\n' "$?"
echo
echo "--- installed versions this host actually reports, for comparison:"
for t in herdr tasks-axi gnhf; do printf '%s: %s\n' "$t" "$(command -v "$t" >/dev/null 2>&1 && "$t" --version 2>&1 | head -1 || echo '<not on PATH>')"; done
env FM_HOME="$H" "$CHECK" disarm; printf '[disarm exit %s]\n' "$?"
rm -rf "$H"

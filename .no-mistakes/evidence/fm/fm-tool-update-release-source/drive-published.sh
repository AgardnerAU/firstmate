#!/usr/bin/env bash
# Live driver for the published-release scenarios of fm-tool-update-check.sh.
# Usage: drive-published.sh <lab-home> <worktree>
set -u
LAB=$1
WT=$2
mkdir -p "$LAB/fakebin"
mk() { printf '#!/bin/sh\necho "%s"\nexit %s\n' "$2" "${3:-0}" > "$LAB/fakebin/$1"; chmod +x "$LAB/fakebin/$1"; }
chk() {
  rm -f "$LAB/state/.tool-updates"
  env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_CONFIG_OVERRIDE \
    PATH="$LAB/fakebin:$PATH" FM_HOME="$LAB" FM_TOOL_UPDATE_INTERVAL=0 FM_TOOL_UPDATE_PROBE_SECS=10 \
    "$WT/bin/fm-tool-update-check.sh" check
  echo "exit=$?"
}
cfg() { printf '%s' "$1" > "$LAB/config/watched-tools.json"; echo "config: $1"; }

echo "## S2: older tasks-axi (0.0.1) and gnhf (v0.0.9) resolve first on PATH -> npm latest is newer"
mk tasks-axi 0.0.1; mk gnhf "gnhf v0.0.9"
cfg '{"tools":[{"name":"tasks-axi","command":"tasks-axi","published":{"source":"npm","package":"tasks-axi"}},{"name":"gnhf","command":"gnhf","published":{"source":"npm","package":"gnhf"}}]}'
chk
echo
echo "## S3: installed copies newer than any published release (999.0.0) -> silent"
mk tasks-axi 999.0.0; mk gnhf 999.0.0
chk
echo
rm -f "$LAB/fakebin/tasks-axi" "$LAB/fakebin/gnhf"
echo "## S4: real installed tasks-axi $(tasks-axi --version) and gnhf $(gnhf --version), no fakes -> silent when current"
chk
echo
echo "## S5: scoped npm package (@anthropic-ai/claude-code) with an old command"
mk claude-old 0.0.1
cfg '{"tools":[{"name":"claude-code","command":"claude-old","published":{"source":"npm","package":"@anthropic-ai/claude-code"}}]}'
chk
echo
echo "## S6: npm package that does not exist -> loud check failure, never reported current"
cfg '{"tools":[{"name":"ghost","command":"claude-old","published":{"source":"npm","package":"zz-no-such-package-fm-lab-9f3a"}}]}'
chk
echo
echo "## S7: published entry whose version probe prints 0.0.1 but exits 3 -> check failure, no comparison"
mk tasks-axi 0.0.1 3
cfg '{"tools":[{"name":"tasks-axi","command":"tasks-axi","published":{"source":"npm","package":"tasks-axi"}}]}'
chk
echo
echo "## S8: entry WITHOUT published: resolved copy prints 1.0.0 and exits 3, a later PATH copy prints 2.0.0 -> PATH skew still read"
mkdir -p "$LAB/fakebin2"
printf '#!/bin/sh\necho 2.0.0\n' > "$LAB/fakebin2/skewtool"; chmod +x "$LAB/fakebin2/skewtool"
mk skewtool 1.0.0 3
cfg '{"tools":[{"name":"skewtool","command":"skewtool"}]}'
rm -f "$LAB/state/.tool-updates"
env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_CONFIG_OVERRIDE \
  PATH="$LAB/fakebin:$LAB/fakebin2:$PATH" FM_HOME="$LAB" FM_TOOL_UPDATE_INTERVAL=0 \
  "$WT/bin/fm-tool-update-check.sh" check
echo "exit=$?"
echo
echo "## S9: malformed published entries -> arm refuses loudly; check reports a registry failure"
for c in \
  '{"tools":[{"name":"x","command":"tasks-axi","published":{"source":"pypi","package":"x"}}]}' \
  '{"tools":[{"name":"x","command":"tasks-axi","published":{"source":"npm","package":"https://evil/x"}}]}' \
  '{"tools":[{"name":"x","published":{"source":"npm","package":"x"}}]}' \
  '{"tools":[{"name":"x","command":"tasks-axi","published":{"source":"github","repo":"a/b","token":"t"}}]}'; do
  cfg "$c"
  env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_CONFIG_OVERRIDE FM_HOME="$LAB" "$WT/bin/fm-tool-update-check.sh" arm
  echo "arm exit=$?"
  chk
done
echo
echo "## S10: GitHub source (herdrdev/herdr) with an old herdr 0.0.1"
mk herdr "herdr 0.0.1"
cfg '{"tools":[{"name":"herdr","command":"herdr","published":{"source":"github","repo":"herdrdev/herdr"}}]}'
chk

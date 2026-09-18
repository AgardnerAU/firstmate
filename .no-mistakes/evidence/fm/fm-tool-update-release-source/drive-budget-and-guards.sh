#!/usr/bin/env bash
# Second live pass: the budget-exhaustion decision (a partial sweep records its
# findings and advances the cadence) and the published-entry validation guards.
set -u
W=/Users/agardner/.no-mistakes/worktrees/c272d8f3fc4c/01M2TDFZN9WFMBX2HPJ48ZPHP0
CHECK="$W/bin/fm-tool-update-check.sh"
H=$(mktemp -d /tmp/fm-live-XXXXXX)
mkdir -p "$H/state" "$H/config" "$H/bin"
printf '#!/usr/bin/env bash\nsleep 30\nprintf "0.0.1\\n"\n' > "$H/bin/slow-live-fixture"
printf '#!/usr/bin/env bash\nprintf "0.1.1\\n"\n' > "$H/bin/gnhf-live-fixture"
chmod 0755 "$H/bin/slow-live-fixture" "$H/bin/gnhf-live-fixture"
echo "home=$H"

echo
echo "=== S9: the slow tool eats the whole 3s budget, so the later tool is never reached ==="
cat > "$H/config/watched-tools.json" <<'JSON'
{"tools":[
 {"name":"slow","command":"slow-live-fixture"},
 {"name":"later","command":"gnhf-live-fixture","published":{"source":"npm","package":"gnhf"}}
]}
JSON
sweep() {
  env FM_HOME="$H" PATH="$H/bin:$PATH" FM_CHECK_TIMEOUT=30 FM_TOOL_UPDATE_INTERVAL=900 \
    FM_TOOL_UPDATE_BUDGET_SECS=3 FM_TOOL_UPDATE_PROBE_SECS=5 "$CHECK" check
  printf '[exit %s]\n' "$?"
}
sweep
echo "--- record left by the incomplete sweep:"
sed -e 's/^epoch=.*/epoch=<an epoch, i.e. the cadence advanced>/' "$H/state/.tool-updates"
echo "--- immediate second poll inside the 900s interval (expect silence: the cadence advanced):"
sweep

echo
echo "=== S8d: published on an entry with no version command is refused by name ==="
cat > "$H/config/watched-tools.json" <<'JSON'
{"tools":[{"name":"bad","git":{"repo":"/tmp"},"published":{"source":"npm","package":"gnhf"}}]}
JSON
rm -f "$H/state/.tool-updates"
env FM_HOME="$H" PATH="$H/bin:$PATH" FM_CHECK_TIMEOUT=30 FM_TOOL_UPDATE_INTERVAL=0 "$CHECK" check
printf '[exit %s]\n' "$?"

echo
echo "=== S8e: a package name that tries to escape its URL path is refused ==="
cat > "$H/config/watched-tools.json" <<'JSON'
{"tools":[{"name":"bad","command":"gnhf-live-fixture","published":{"source":"npm","package":"../../evil"}}]}
JSON
rm -f "$H/state/.tool-updates"
env FM_HOME="$H" PATH="$H/bin:$PATH" FM_CHECK_TIMEOUT=30 FM_TOOL_UPDATE_INTERVAL=0 "$CHECK" check
printf '[exit %s]\n' "$?"

echo
echo "=== S8f: a GitHub repo given as a URL is refused ==="
cat > "$H/config/watched-tools.json" <<'JSON'
{"tools":[{"name":"bad","command":"gnhf-live-fixture","published":{"source":"github","repo":"https://github.com/cli/cli"}}]}
JSON
rm -f "$H/state/.tool-updates"
env FM_HOME="$H" PATH="$H/bin:$PATH" FM_CHECK_TIMEOUT=30 FM_TOOL_UPDATE_INTERVAL=0 "$CHECK" check
printf '[exit %s]\n' "$?"

echo
echo "=== S8g: an unsupported extra published field is refused ==="
cat > "$H/config/watched-tools.json" <<'JSON'
{"tools":[{"name":"bad","command":"gnhf-live-fixture","published":{"source":"github","repo":"cli/cli","tag":"v2.0.0"}}]}
JSON
rm -f "$H/state/.tool-updates"
env FM_HOME="$H" PATH="$H/bin:$PATH" FM_CHECK_TIMEOUT=30 FM_TOOL_UPDATE_INTERVAL=0 "$CHECK" check
printf '[exit %s]\n' "$?"

echo
echo "=== S10: a watched command missing from PATH is still reported, with no published comparison ==="
cat > "$H/config/watched-tools.json" <<'JSON'
{"tools":[{"name":"absent","command":"fm-absent-live-fixture","published":{"source":"npm","package":"gnhf"}}]}
JSON
rm -f "$H/state/.tool-updates"
env FM_HOME="$H" PATH="$H/bin:$PATH" FM_CHECK_TIMEOUT=30 FM_TOOL_UPDATE_INTERVAL=0 "$CHECK" check
printf '[exit %s]\n' "$?"

rm -rf "$H"

#!/usr/bin/env bash
# Drives bin/fm-tool-update-check.sh the way an operator runs it: an isolated
# FM_HOME, a real watched-tools registry, synthetic installed copies on PATH,
# and real HTTP queries to the public npm registry and GitHub release API.
set -u
W=/Users/agardner/.no-mistakes/worktrees/c272d8f3fc4c/01M2TDFZN9WFMBX2HPJ48ZPHP0
CHECK="$W/bin/fm-tool-update-check.sh"
H=$(mktemp -d /tmp/fm-live-XXXXXX)
mkdir -p "$H/state" "$H/config" "$H/bin"

mk() {
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %s\n' "'$2'" > "$H/bin/$1"
  chmod 0755 "$H/bin/$1"
}

run() {
  env FM_HOME="$H" PATH="$H/bin:$PATH" FM_CHECK_TIMEOUT=30 FM_TOOL_UPDATE_INTERVAL=0 "$@" "$CHECK" check
  printf '[exit %s]\n' "$?"
}

echo "home=$H"
echo
echo "=== S1/S2: real npm and real GitHub published sources, installed copies behind ==="
mk gnhf-live-fixture '0.1.1'
mk ghcli-live-fixture 'gh version 2.0.0 (2021-01-01)'
cat > "$H/config/watched-tools.json" <<'JSON'
{"tools":[
 {"name":"gnhf","command":"gnhf-live-fixture","published":{"source":"npm","package":"gnhf"}},
 {"name":"gh","command":"ghcli-live-fixture","published":{"source":"github","repo":"cli/cli"}}
]}
JSON
run

echo
echo "=== S4a: an identical second sweep is deduplicated (expect silence) ==="
run

echo
echo "=== S3: installed copies at or ahead of published stay silent ==="
rm -f "$H/state/.tool-updates"
mk gnhf-live-fixture '99.0.0'
mk ghcli-live-fixture 'gh version 99.0.0 (2026-01-01)'
run

echo
echo "=== S4b: a changed installed version is news again ==="
mk gnhf-live-fixture '0.1.2'
run

echo
echo "=== S7: huge version components compare without arithmetic overflow ==="
rm -f "$H/state/.tool-updates"
mk gnhf-live-fixture '0.99999999999999999999999999'
cat > "$H/config/watched-tools.json" <<'JSON'
{"tools":[{"name":"gnhf","command":"gnhf-live-fixture","published":{"source":"npm","package":"gnhf"}}]}
JSON
echo "installed 0.99999999999999999999999999 against published 0.1.x (expect silence):"
run

echo
echo "=== S5: an unpublished package is a per-tool check failure, and the sweep goes on ==="
rm -f "$H/state/.tool-updates"
mk gnhf-live-fixture '0.1.1'
mk other-live-fixture '1.0.0'
cat > "$H/config/watched-tools.json" <<'JSON'
{"tools":[
 {"name":"ghost","command":"gnhf-live-fixture","published":{"source":"npm","package":"fm-no-such-package-live-fixture-zzz"}},
 {"name":"ghost-gh","command":"gnhf-live-fixture","published":{"source":"github","repo":"fm-no-such-owner-zzz/fm-no-such-repo-zzz"}},
 {"name":"other","command":"other-live-fixture","published":{"source":"npm","package":"gnhf"}}
]}
JSON
run

echo
echo "=== S6: a version command that fails is not a usable baseline ==="
rm -f "$H/state/.tool-updates"
printf '#!/bin/sh\nprintf "0.0.1\\n"\nexit 1\n' > "$H/bin/gnhf-live-fixture"
chmod 0755 "$H/bin/gnhf-live-fixture"
cat > "$H/config/watched-tools.json" <<'JSON'
{"tools":[{"name":"gnhf","command":"gnhf-live-fixture","published":{"source":"npm","package":"gnhf"}}]}
JSON
run

echo
echo "=== S8: a malformed published entry refuses the whole registry, at arm and at check ==="
mk gnhf-live-fixture '0.1.1'
cat > "$H/config/watched-tools.json" <<'JSON'
{"tools":[
 {"name":"good","command":"gnhf-live-fixture"},
 {"name":"bad","command":"gnhf-live-fixture","published":{"source":"sourceforge","package":"gnhf"}}
]}
JSON
rm -f "$H/state/.tool-updates"
echo "--- arm:"
env FM_HOME="$H" PATH="$H/bin:$PATH" "$CHECK" arm; echo "[exit $?]"
echo "--- shim present? $( [ -e "$H/state/tool-updates.check.sh" ] && echo yes || echo no)"
echo "--- check:"
run

echo
echo "=== S8b: published without a version command is refused too ==="
cat > "$H/config/watched-tools.json" <<'JSON'
{"tools":[{"name":"bad","published":{"source":"npm","package":"gnhf"}}]}
JSON
run
echo
echo "=== S8c: a valid registry arms cleanly ==="
cat > "$H/config/watched-tools.json" <<'JSON'
{"tools":[{"name":"gnhf","command":"gnhf-live-fixture","published":{"source":"npm","package":"gnhf"}}]}
JSON
env FM_HOME="$H" PATH="$H/bin:$PATH" "$CHECK" arm; echo "[arm exit $?]"
echo "--- shim: $(cat "$H/state/tool-updates.check.sh")"
echo "--- dispatching the armed shim the way the watcher does:"
rm -f "$H/state/.tool-updates"
env PATH="$H/bin:$PATH" FM_CHECK_TIMEOUT=30 FM_TOOL_UPDATE_INTERVAL=0 "$H/state/tool-updates.check.sh"; echo "[exit $?]"
env FM_HOME="$H" PATH="$H/bin:$PATH" "$CHECK" disarm; echo "[disarm exit $?]"

echo
echo "=== S9: a sweep that runs out of budget records its partial findings and advances the cadence ==="
rm -f "$H/state/.tool-updates"
cat > "$H/bin/slow-live-fixture" <<'SH'
#!/usr/bin/env bash
sleep 30
printf '0.0.1\n'
SH
chmod 0755 "$H/bin/slow-live-fixture"
cat > "$H/config/watched-tools.json" <<'JSON'
{"tools":[
 {"name":"slow","command":"slow-live-fixture"},
 {"name":"later","command":"gnhf-live-fixture","published":{"source":"npm","package":"gnhf"}}
]}
JSON
echo "--- sweep with a 3s budget (expect an incomplete report):"
env FM_HOME="$H" PATH="$H/bin:$PATH" FM_CHECK_TIMEOUT=30 FM_TOOL_UPDATE_INTERVAL=900 \
  FM_TOOL_UPDATE_BUDGET_SECS=3 FM_TOOL_UPDATE_PROBE_SECS=2 "$CHECK" check
printf '[exit %s]\n' "$?"
echo "--- record written by that incomplete sweep:"
sed -e 's/^epoch=.*/epoch=<redacted>/' "$H/state/.tool-updates"
echo "--- immediate second poll inside the 900s interval (expect silence, no probes):"
env FM_HOME="$H" PATH="$H/bin:$PATH" FM_CHECK_TIMEOUT=30 FM_TOOL_UPDATE_INTERVAL=900 \
  FM_TOOL_UPDATE_BUDGET_SECS=3 FM_TOOL_UPDATE_PROBE_SECS=2 "$CHECK" check
printf '[exit %s]\n' "$?"

echo
echo "cleanup: $H"
rm -rf "$H"

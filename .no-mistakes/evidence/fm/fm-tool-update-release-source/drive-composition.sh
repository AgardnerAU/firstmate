#!/usr/bin/env bash
# Third live pass: the detection that already worked (PATH skew, the tool's own
# update announcement, and a git clone behind its remote) still reports while a
# published source is configured on the same tool.
set -u
W=/Users/agardner/.no-mistakes/worktrees/c272d8f3fc4c/01M2TDFZN9WFMBX2HPJ48ZPHP0
CHECK="$W/bin/fm-tool-update-check.sh"
H=$(mktemp -d /tmp/fm-live-XXXXXX)
mkdir -p "$H/state" "$H/config" "$H/bin" "$H/fresh"
echo "home=$H"

printf '#!/usr/bin/env bash\nprintf "gnhf 0.1.1 (update to 0.1.49 available)\\n"\n' > "$H/bin/gnhf-live-fixture"
printf '#!/usr/bin/env bash\nprintf "gnhf 0.1.2\\n"\n' > "$H/fresh/gnhf-live-fixture"
chmod 0755 "$H/bin/gnhf-live-fixture" "$H/fresh/gnhf-live-fixture"

# A real upstream clone that is one commit behind its remote.
export GIT_AUTHOR_NAME=fmtest GIT_AUTHOR_EMAIL=fmtest@example.invalid
export GIT_COMMITTER_NAME=fmtest GIT_COMMITTER_EMAIL=fmtest@example.invalid
git init -q -b main "$H/upstream"
( cd "$H/upstream" && echo one > f && git add f && git commit -qm one )
git clone -q "$H/upstream" "$H/clone"
( cd "$H/upstream" && echo two > f && git commit -qam two )

cat > "$H/config/watched-tools.json" <<JSON
{"tools":[{"name":"gnhf","command":"gnhf-live-fixture",
  "announce_pattern":"update to [0-9.]+",
  "published":{"source":"npm","package":"gnhf"},
  "git":{"repo":"$H/clone","branch":"main"}}]}
JSON

echo
echo "=== S11: all four sources report together for one watched tool ==="
env FM_HOME="$H" PATH="$H/bin:$H/fresh:$PATH" FM_CHECK_TIMEOUT=30 FM_TOOL_UPDATE_INTERVAL=0 \
  FM_TOOL_UPDATE_BUDGET_SECS=30 "$CHECK" check
printf '[exit %s]\n' "$?"
rm -rf "$H"

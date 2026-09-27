#!/usr/bin/env bash
# Live drive of fm-tool-update-check.sh against the real npm registry and GitHub API.
set -u
WT=/Users/agardner/.no-mistakes/worktrees/c272d8f3fc4c/01M3GZPG33ZNR12AQ7XG8DEK2V
H=$(mktemp -d "${TMPDIR:-/tmp}/fm-live-pub.XXXXXX")
mkdir -p "$H/state" "$H/config" "$H/old" "$H/new" "$H/sys"
for t in curl jq bash env sed awk date mkdir rm mv cat grep tr head tail sort uniq wc dirname basename mktemp printf sleep kill ps cut perl python3 git stat chmod ln readlink tee od cmp; do p=$(command -v $t 2>/dev/null) && ln -sf "$p" "$H/sys/$t"; done
mk() { printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\nexit %s\n' "$3" "${4:-0}" > "$1/$2"; chmod 755 "$1/$2"; }
run() { env -u NO_MISTAKES_GATE -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_DATA_OVERRIDE \
  FM_HOME="$H" FM_TOOL_UPDATE_INTERVAL=0 FM_TOOL_UPDATE_PROBE_SECS=10 FM_TOOL_UPDATE_BUDGET_SECS=25 \
  PATH="$1:$H/sys" "$WT/bin/fm-tool-update-check.sh" check; echo "[exit=$?]"; rm -f "$H/state/.tool-updates"; }
echo "== S1: example registry entries (herdr github, tasks-axi npm, gnhf npm), installed 0.0.1 =="
cp "$WT/docs/examples/watched-tools.json" "$H/config/watched-tools.json"
jq '{tools: [.tools[] | select(.published)]}' "$H/config/watched-tools.json" > "$H/c" && mv "$H/c" "$H/config/watched-tools.json"
jq -c '.tools[]' "$H/config/watched-tools.json"
mk "$H/old" herdr "herdr 0.0.1"; mk "$H/old" tasks-axi "0.0.1"; mk "$H/old" gnhf "gnhf 0.0.1"
run "$H/old"
echo "== S2: installed far ahead (99.0.0) -> expect silence =="
mk "$H/old" herdr "herdr 99.0.0"; mk "$H/old" tasks-axi "99.0.0"; mk "$H/old" gnhf "gnhf 99.0.0"
run "$H/old"
echo "== S3: learn real published versions from S1 output, then install exactly those -> expect silence =="
mk "$H/old" herdr "herdr 0.0.1"; mk "$H/old" tasks-axi "0.0.1"; mk "$H/old" gnhf "gnhf 0.0.1"
out=$(run "$H/old")
HV=$(printf '%s\n' "$out" | sed -n 's/.*herdr update available: installed 0.0.1, published \([0-9.]*\) at.*/\1/p')
TV=$(printf '%s\n' "$out" | sed -n 's/.*tasks-axi update available: installed 0.0.1, published \([0-9.]*\) at.*/\1/p')
GV=$(printf '%s\n' "$out" | sed -n 's/.*gnhf update available: installed 0.0.1, published \([0-9.]*\) at.*/\1/p')
echo "published: herdr=$HV tasks-axi=$TV gnhf=$GV"
mk "$H/old" herdr "herdr $HV"; mk "$H/old" tasks-axi "$TV"; mk "$H/old" gnhf "gnhf $GV"
run "$H/old"
echo "== S4 (adversarial, #5786 rule): PATH resolves 0.0.1, newer copy at published $GV also installed -> only 'not in effect' =="
jq '{tools: [.tools[] | select(.name=="gnhf")]}' "$H/config/watched-tools.json" > "$H/c" && mv "$H/c" "$H/config/watched-tools.json"
mk "$H/old" gnhf "gnhf 0.0.1"; mk "$H/new" gnhf "gnhf $GV"
run "$H/old:$H/new"
echo "== S5 (adversarial): installed command exits non-zero -> published comparison refused with check failure =="
rm -f "$H/new/gnhf"; mk "$H/old" gnhf "gnhf 0.0.1" 3
run "$H/old"
echo "== S6 (adversarial): nonexistent npm package / github repo -> per-tool check failure, sweep continues =="
mk "$H/old" gnhf "gnhf 0.0.1"; mk "$H/old" herdr "herdr 0.0.1"
printf '%s\n' '{"tools":[{"name":"ghost","command":"herdr","published":{"source":"github","repo":"kunchenguid/fm-no-such-repo-zz9"}},{"name":"ghost-npm","command":"gnhf","published":{"source":"npm","package":"fm-no-such-pkg-zz9-qq"}},{"name":"gnhf","command":"gnhf","published":{"source":"npm","package":"gnhf"}}]}' > "$H/config/watched-tools.json"
run "$H/old"
echo "== S7 (adversarial): malformed published entry refuses whole registry =="
printf '%s\n' '{"tools":[{"name":"gnhf","command":"gnhf","published":{"source":"npm","package":"gnhf"}},{"name":"bad","command":"gnhf","published":{"source":"github","repo":"https://github.com/herdrdev/herdr"}}]}' > "$H/config/watched-tools.json"
run "$H/old"
echo "== S8: entry without published: non-zero-exit probe still reports version (PATH skew) and never touches network =="
printf '%s\n' '{"tools":[{"name":"gnhf","command":"gnhf"}]}' > "$H/config/watched-tools.json"
mk "$H/old" gnhf "gnhf 0.0.1" 2; mk "$H/new" gnhf "gnhf 0.0.5" 2
run "$H/old:$H/new"
rm -rf "$H"

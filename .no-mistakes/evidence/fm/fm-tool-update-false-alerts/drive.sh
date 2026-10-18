#!/usr/bin/env bash
# Live driver: runs the real fm-tool-update-check.sh (this branch, and the base
# commit for comparison) against a disposable FM_HOME with fixture tools.
set -u
WT=/Users/agardner/.no-mistakes/worktrees/c272d8f3fc4c/01M57FN8JSQ6GH0HYQXBK60E3W
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-tuc-lab.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
mkdir -p "$LAB/base"; git -C "$WT" archive 1aa2a21ec35e2d0644ac836b7b5d3cb36669ef33 bin | tar -x -C "$LAB/base"
NEW="$WT/bin/fm-tool-update-check.sh"; OLD="$LAB/base/bin/fm-tool-update-check.sh"
B="$LAB/tools"; mkdir -p "$B"
# "axi" tools: --version is fast, `update --check` does a slow network round trip
mk_axi() { cat > "$B/$1" <<SH
#!/usr/bin/env bash
if [ "\$1" = update ]; then sleep $2; echo "update: package $1, current 0.1.0, latest 0.1.0, available false"; exit 0; fi
echo "$1 0.1.0"
SH
chmod +x "$B/$1"; }
mk_axi gh-axi-fx 4; mk_axi quota-axi-fx 4; mk_axi chrome-axi-fx 4
for t in tasks-axi-fx lavish-axi-fx; do printf '#!/usr/bin/env bash\necho "%s 0.2.5"\n' $t > "$B/$t"; chmod +x "$B/$t"; done
axi() { printf '{"name":"%s","command":"%s","announce_args":["update","--check"],"announce_pattern":"available true"}' "${1%-fx}" "$1"; }
plain() { printf '{"name":"%s","command":"%s"}' "${1%-fx}" "$1"; }
home() { local h="$LAB/home-$1"; mkdir -p "$h/state" "$h/config"; echo "$h"; }
run() { local script=$1 h=$2; shift 2
  env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_CONFIG_OVERRIDE FM_CHECK_TIMEOUT=30 FM_TOOL_UPDATE_INTERVAL=0 "$@" FM_HOME="$h" PATH="$B:$PATH" bash "$script" check; echo "[exit=$?]"; }

echo "===== S1: 2026-09-16 shape - three slow update --check probes + two tools after them, sweep budget 10s, probe bound 5s"
CFG="{\"tools\":[$(axi gh-axi-fx),$(axi quota-axi-fx),$(axi chrome-axi-fx),$(plain tasks-axi-fx),$(plain lavish-axi-fx)]}"
for which in OLD NEW; do h=$(home s1-$which); echo "$CFG" > "$h/config/watched-tools.json"
  echo "--- $which (${which/OLD/base 1aa2a21e}${which/NEW/branch 29fb827c})"; run "${!which}" "$h" FM_TOOL_UPDATE_BUDGET_SECS=10 FM_TOOL_UPDATE_PROBE_SECS=5; done

echo; echo "===== S2: one tool whose announce probe overruns its own bound (probe 2s, tool takes 4s, ample budget)"
CFG="{\"tools\":[$(axi gh-axi-fx)]}"
for which in OLD NEW; do h=$(home s2-$which); echo "$CFG" > "$h/config/watched-tools.json"
  echo "--- $which"; run "${!which}" "$h" FM_TOOL_UPDATE_PROBE_SECS=2; done

echo; echo "===== S3: adversarial - a genuinely broken tool is still a check failure, distinguishable from timeouts"
printf '#!/usr/bin/env bash\necho "garbage"\n' > "$B/broken-fx"; chmod +x "$B/broken-fx"
h=$(home s3); echo "{\"tools\":[$(plain broken-fx),{\"name\":\"absent\",\"command\":\"absent-fx-nope\"}]}" > "$h/config/watched-tools.json"
run "$NEW" "$h"

echo; echo "===== S4: 2026-09-13 set flap - A=pending no-mistakes update, B=slow lavish probe that flaps"
cat > "$B/nm-fx" <<'SH'
#!/usr/bin/env bash
[ "$1" = --version ] && { echo "no-mistakes version v1.64.0"; exit 0; }
echo "A new version of no-mistakes is available: v1.64.0 -> v1.72.0"
SH
chmod +x "$B/nm-fx"
cat > "$B/lav-fx" <<SH
#!/usr/bin/env bash
[ "\$1" = --version ] && { echo "lavish 0.1.67"; exit 0; }
[ -e "$LAB/slow" ] && sleep 4; echo ok
SH
chmod +x "$B/lav-fx"
CFG='{"tools":[{"name":"no-mistakes","command":"nm-fx","version_args":["--version"],"announce_args":["--help"],"announce_pattern":"A new version of no-mistakes is available: [^ ]+ -> [^ ]+"},{"name":"lavish-axi","command":"lav-fx","announce_args":["update","--check"],"announce_pattern":"available true"}]}'
for which in OLD NEW; do h=$(home s4-$which); echo "$CFG" > "$h/config/watched-tools.json"; echo "--- $which"
  for sweep in "1 slow" "2 fast" "3 slow" "4 slow" "5 fast"; do set -- $sweep
    if [ "$2" = slow ]; then touch "$LAB/slow"; else rm -f "$LAB/slow"; fi
    printf 'sweep %s (lavish %s): ' "$1" "$2"; out=$(run "${!which}" "$h" FM_TOOL_UPDATE_PROBE_SECS=2); echo "${out//$'\n'/ }"
  done
  echo "record after sweep 5:"; sed 's/^/    /' "$h/state/.tool-updates"; done

echo; echo "===== S5: unreached-tool list flaps (C,D unreached, then only D) - D not re-announced"
mk_axi slowtool-fx 30; for t in c-fx d-fx; do printf '#!/usr/bin/env bash\necho "%s 1.0.0"\n' $t > "$B/$t"; chmod +x "$B/$t"; done
h=$(home s5)
echo "{\"tools\":[$(axi slowtool-fx),$(plain c-fx),$(plain d-fx)]}" > "$h/config/watched-tools.json"
printf 'sweep 1: '; run "$NEW" "$h" FM_TOOL_UPDATE_PROBE_SECS=10 FM_TOOL_UPDATE_BUDGET_SECS=2 | tr '\n' ' '; echo
echo "{\"tools\":[$(axi slowtool-fx),$(plain d-fx)]}" > "$h/config/watched-tools.json"
printf 'sweep 2 (C reached/removed, D still unreached): '; run "$NEW" "$h" FM_TOOL_UPDATE_PROBE_SECS=10 FM_TOOL_UPDATE_BUDGET_SECS=2 | tr '\n' ' '; echo

echo; echo "===== S6: version_url read out of time"
printf '#!/usr/bin/env bash\necho "2.1.271 (Claude Code)"\n' > "$B/claude-fx"; chmod +x "$B/claude-fx"
CB="$LAB/curl28"; mkdir -p "$CB"; printf '#!/usr/bin/env bash\nexit 28\n' > "$CB/curl"; chmod +x "$CB/curl"
CS="$LAB/curlslow"; mkdir -p "$CS"; printf '#!/usr/bin/env bash\nsleep 30; echo 2.1.273\n' > "$CS/curl"; chmod +x "$CS/curl"
CE="$LAB/curlempty"; mkdir -p "$CE"; printf '#!/usr/bin/env bash\necho "no version here"\n' > "$CE/curl"; chmod +x "$CE/curl"
CFG='{"tools":[{"name":"claude","command":"claude-fx","version_url":"https://downloads.example.invalid/latest"}]}'
for c in "curl28:curl exits 28 (own --max-time)" "curlslow:curl hangs, budget 2s < probe 10s" "curlempty:curl answers with no version"; do d=${c%%:*}
  h=$(home s6-$d); echo "$CFG" > "$h/config/watched-tools.json"; printf '%s: ' "${c#*:}"
  extra=(); [ $d = curlslow ] && extra=(FM_TOOL_UPDATE_PROBE_SECS=10 FM_TOOL_UPDATE_BUDGET_SECS=2)
  env -u FM_ROOT_OVERRIDE FM_CHECK_TIMEOUT=30 FM_TOOL_UPDATE_INTERVAL=0 ${extra[@]+"${extra[@]}"} FM_HOME="$h" PATH="$LAB/$d:$B:$PATH" bash "$NEW" check | tr '\n' ' '; echo
done

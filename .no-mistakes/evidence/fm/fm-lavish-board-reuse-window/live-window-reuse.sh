#!/usr/bin/env bash
# Live drive of bin/fm-bearings-board.sh build against the REAL lavish-axi
# (isolated server: own LAVISH_AXI_STATE_DIR and LAVISH_AXI_PORT). Only the
# macOS `open` launcher is shadowed, so every browser-window launch lavish-axi
# makes is logged instead of popping a window on the operator desktop.
set -u
WT=/Users/agardner/.no-mistakes/worktrees/c272d8f3fc4c/01M3B3T3W2YBAAJ5A11RF3HHMR
LAB=$(mktemp -d /tmp/fm-lab-lavish-window.XXXXXX)
mkdir -p "$LAB/home/state" "$LAB/home/data" "$LAB/lavish-state" "$LAB/bin" "$LAB/claims"
cat > "$LAB/bin/open" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$LAB/window-opens.log"
SH
chmod +x "$LAB/bin/open"
export PATH="$LAB/bin:$PATH" FM_HOME="$LAB/home" FM_STATE_OVERRIDE="$LAB/home/state" \
  FM_DATA_OVERRIDE="$LAB/home/data" FM_PROCEVENT_CLAIM_ROOT="$LAB/claims" \
  LAVISH_AXI_STATE_DIR="$LAB/lavish-state" LAVISH_AXI_PORT=43987 LAVISH_AXI_HOST=127.0.0.1
unset LAVISH_AXI_NO_OPEN
BOARD="$WT/bin/fm-bearings-board.sh"
# Reuse the suite's valid payload fixture.
eval "$(sed -n '/^write_valid_payload() {/,/^EOF$/p' "$WT/tests/fm-bearings-board.test.sh"; echo '}')"
write_valid_payload "$LAB/payload.json"
opens() { [ -f "$LAB/window-opens.log" ] && wc -l < "$LAB/window-opens.log" | tr -d ' ' || echo 0; }
FAILS=0
check() { if [ "$2" = "$3" ]; then echo "PASS: $1 (got $2)"; else echo "FAIL: $1 (expected $3, got $2)"; FAILS=$((FAILS+1)); fi; }
build() { echo "--- build: $1"; local before; before=$(opens); "$BOARD" build "$LAB/payload.json" 2>&1 | sed 's/^/    /'; echo "    [build exit ${PIPESTATUS[0]}]"; DELTA=$(( $(opens) - before )); echo "    window launches this build: $DELTA"; }
listing() { echo "--- lavish-axi session listing (sessions table)"; lavish-axi 2>&1 | awk '/^sessions/{p=1;print;next} p&&/^  /{print;next} {p=0}' | sed 's/^/    /'; }
echo "lavish-axi version: $(lavish-axi --version)"
echo "lab: $LAB"
build "S1 first build (no session yet)"; check "S1 first build opens exactly one window" "$DELTA" 1
build "S2 rebuild while session open"; check "S2 rebuild of open session opens no window" "$DELTA" 0
for i in 1 2 3; do build "S3 repeated rebuild #$i"; check "S3 repeated rebuild #$i opens no window" "$DELTA" 0; done
listing
n=$(lavish-axi 2>/dev/null | grep -c 'bearings-board.html,open'); check "S6 exactly one open board session after rebuilds (none closed, none duplicated)" "$n" 1
board=$("$BOARD" path)
echo "--- agent ends the session: lavish-axi end"; lavish-axi end "$board" 2>&1 | sed 's/^/    /'
build "S4 rebuild after agent-ended session"; check "S4 rebuild of agent-ended session opens one window" "$DELTA" 1
url=$(lavish-axi 2>/dev/null | grep 'bearings-board.html' | sed -E 's/.*(http[^,]*session\/[0-9a-f]+).*/\1/' | head -1)
key=${url##*/}
echo "--- captain ends the session from the browser: POST /api/$key/end"
curl -s -X POST -H 'content-type: application/json' "http://127.0.0.1:43987/api/$key/end" -d '{}'; echo
build "S5 rebuild after captain-ended session"; check "S5 rebuild reopening a captain-ended session opens one window" "$DELTA" 1
build "S5b rebuild after the reopen"; check "S5b rebuild after reopen opens no window" "$DELTA" 0
listing
echo "--- all window launches recorded by the shadowed open(1):"; sed 's/^/    /' "$LAB/window-opens.log"
echo "--- teardown"
"$WT/bin/fm-procevent.sh" sweep-home >/dev/null 2>&1 || true
lavish-axi stop 2>&1 | sed 's/^/    /'
pkill -f "$LAB" 2>/dev/null || true
sleep 1; pgrep -fl "$LAB" || echo "    no lab processes remain"
rm -rf "$LAB"
echo "RESULT: $FAILS failure(s)"

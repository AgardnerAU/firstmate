#!/usr/bin/env bash
# Live lab proof for fm_backend_herdr_capture viewport cap (guarded fm-lab session).
set -u
ROOT=${ROOT:?}
HERDR_LAB_HELPER=$ROOT/bin/fm-herdr-lab.sh
REAL_HERDR=$(command -v herdr); HERDR_ORIGINAL_PATH=$PATH
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-herdr-capture-live.XXXXXX"); FAKEBIN=$TMP_ROOT/fakebin; mkdir -p "$FAKEBIN"
HERDR_LAB_SESSION=$("$HERDR_LAB_HELPER" name capture-vp)
export HERDR_LAB_HELPER HERDR_LAB_SESSION REAL_HERDR HERDR_ORIGINAL_PATH
cleanup(){ local s=$?; env PATH="$HERDR_ORIGINAL_PATH" "$HERDR_LAB_HELPER" teardown "$HERDR_LAB_SESSION" || s=1; rm -rf "$TMP_ROOT"; echo "teardown exit-status=$s"; exit $s; }
trap cleanup EXIT
"$HERDR_LAB_HELPER" provision "$HERDR_LAB_SESSION" || exit 1
cat > "$FAKEBIN/herdr" <<'SH'
#!/usr/bin/env bash
set -u
args=("$@"); last=$((${#args[@]} - 1)); flag=$((last - 1))
if [ "${#args[@]}" -ge 2 ] && [ "${args[$flag]}" = --session ] && [ "${args[$last]}" = "$HERDR_LAB_SESSION" ]; then unset "args[$last]" "args[$flag]"; fi
set -- "${args[@]}"
for a in "$@"; do case "$a" in --session|--session=*) exit 9;; esac; done
printf '%s\n' "$*" >> "${FM_SHIM_LOG:-/dev/null}"
if [ "${1:-}" = --version ]; then exec env PATH="$HERDR_ORIGINAL_PATH" "$REAL_HERDR" "$@" --session "$HERDR_LAB_SESSION"; fi
exec env PATH="$HERDR_ORIGINAL_PATH" "$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" "$@"
SH
chmod +x "$FAKEBIN/herdr"
lab(){ env PATH="$HERDR_ORIGINAL_PATH" "$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" "$@"; }
export FM_SHIM_LOG=$TMP_ROOT/shim.log
capture(){ : > "$FM_SHIM_LOG"; PATH="$FAKEBIN:$HERDR_ORIGINAL_PATH" bash -c '. "$0/bin/backends/herdr.sh"; fm_backend_herdr_capture "$1" "$2"' "$ROOT" "$HERDR_LAB_SESSION:$PANE" "$1"; }
WS=$(lab workspace create --cwd "$TMP_ROOT" --label capture-lab) || { echo "workspace create failed"; exit 1; }
echo "workspace create: $WS" | head -c 600; echo
PANE=$(printf '%s' "$WS" | jq -r '.. | objects | .pane_id? // empty' | head -1)
echo "PANE=$PANE"
lab pane get "$PANE" | jq -c '.result.pane.scroll'
VR=$(lab pane get "$PANE" | jq -r '.result.pane.scroll.viewport_rows')
echo "viewport_rows=$VR"
echo "=== S1 normal shell: 300 numbered lines ==="
lab pane run "$PANE" 'clear; seq -f "row-%03g" 1 300' >/dev/null; sleep 2
out=$(capture 5); echo "--- capture 5 ->"; printf '%s\n' "$out"; echo "--- herdr calls:"; cat "$FM_SHIM_LOG"
out=$(capture 250); n=$(printf '%s\n' "$out" | wc -l); echo "--- capture 250 -> $n lines (viewport $VR); tail:"; printf '%s\n' "$out" | tail -3; echo "--- herdr calls:"; cat "$FM_SHIM_LOG"
echo "=== S2 alternate-screen pane (less) ==="
lab pane run "$PANE" 'seq -f "alt-%03g" 1 500 | less' >/dev/null; sleep 2
before_vis=$(lab pane read "$PANE" --source visible); before_scroll=$(lab pane get "$PANE" | jq -c '.result.pane.scroll')
echo "before scroll: $before_scroll"
out=$(capture 200); n=$(printf '%s\n' "$out" | grep -c .); echo "--- capture 200 on alt-screen -> $n nonblank lines; head/tail:"; printf '%s\n' "$out" | grep . | head -2; printf '%s\n' "$out" | grep . | tail -2; echo "--- herdr calls:"; cat "$FM_SHIM_LOG"
sleep 1
after_vis=$(lab pane read "$PANE" --source visible); after_scroll=$(lab pane get "$PANE" | jq -c '.result.pane.scroll')
echo "after scroll: $after_scroll"
[ "$before_vis" = "$after_vis" ] && echo "VISIBLE UNCHANGED after capture: yes" || { echo "VISIBLE UNCHANGED after capture: NO"; diff <(echo "$before_vis") <(echo "$after_vis") | head; }
echo "=== S2b old-style over-viewport recent read (--lines 200) for contrast ==="
old=$(lab pane read "$PANE" --source recent --lines 200); echo "old read nonblank lines: $(printf '%s\n' "$old" | grep -c .)"; printf '%s\n' "$old" | grep . | head -3
sleep 1; post_old_vis=$(lab pane read "$PANE" --source visible); echo "post-old scroll: $(lab pane get "$PANE" | jq -c '.result.pane.scroll')"
[ "$after_vis" = "$post_old_vis" ] && echo "visible unchanged after old read: yes" || echo "visible unchanged after old read: NO"
lab pane send-keys "$PANE" q >/dev/null 2>&1; sleep 1
echo "=== S3 bad target pane id fails non-zero ==="
PANE=w999:p999; capture 5; echo "bad-pane capture exit=$?"; cat "$FM_SHIM_LOG"

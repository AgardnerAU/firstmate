#!/usr/bin/env bash
# Drives bin/fm-procevent-lavish.sh poll (the adapter's public listener
# interface) against a disposable FM_HOME and a lavish-axi 0.1.80 stand-in.
# Usage: drive-receipt-poll.sh <worktree> <scratch-dir>
set -u
cd "$1"
W=$2; export W
mkdir -p "$W/bin" "$W/home/state/procevent" "$W/lavish-state" "$W/claims"
cat > "$W/bin/lavish-axi" <<'SH'
#!/usr/bin/env bash
case "${1-}" in
  --version) [ "$MODE" != unknown ] || exit 1; printf '0.1.80\n' ;;
  reply) [ "$MODE" = accept ] || { printf 'session is gone\n' >&2; exit 1; }
         printf 'reply(%s)\n' "$(cat -- "$4")" >> "$W/calls" ;;
  poll) printf 'poll(%s)\n' "${4-}" >> "$W/calls"; printf 'session:\n  status: ended\n' ;;
  *) exit 2 ;;
esac
SH
chmod +x "$W/bin/lavish-axi"
art="$W/board.html"; printf '<h1>board</h1>\n' > "$art"
real=$(perl -MCwd=realpath -e 'print realpath($ARGV[0])' "$art")
key=$(printf '%s' "$real" | shasum -a 256 | cut -c1-16)
printf '{"sessions":{"%s":{"key":"%s","file":"%s","status":"open","url":"http://127.0.0.1:14387/session/0123456789abcdef"}}}' \
  "$key" "$key" "$real" > "$W/lavish-state/state.json"
export LAVISH_AXI_STATE_DIR="$W/lavish-state" FM_PROCEVENT_CLAIM_ROOT="$W/claims" FM_HOME="$W/home" PATH="$W/bin:$PATH"
sid=$(bin/fm-procevent-lavish.sh source-id "$art")
rf="$W/home/state/procevent/.$sid.lavish-receipt"
echo "source-id: $sid"
for MODE in accept refuse unknown; do
  export MODE
  rm -f "$W/calls"; printf 'Recorded: Call A (south). Firstmate will follow up.' > "$rf"
  echo "=== firstmate-owned receipt, lavish-axi mode=$MODE ==="
  out=$(bin/fm-procevent-lavish.sh poll "$art" 2>&1); rc=$?
  echo "exit=$rc"; echo "output:"; echo "$out"
  echo "calls seen by lavish-axi:"; cat "$W/calls"
  if [ -e "$rf" ]; then echo "receipt STILL STAGED"; else echo "receipt consumed"; fi
done
echo "=== task-owned --agent-reply-file, lavish-axi mode=refuse (must stay fail-closed) ==="
export MODE=refuse; rm -f "$W/calls"; tf="$W/task-reply"; printf 'task reply' > "$tf"
out=$(bin/fm-procevent-lavish.sh poll "$art" --agent-reply-file "$tf" 2>&1); rc=$?
echo "exit=$rc"; echo "output:"; echo "$out"
echo "calls:"; cat "$W/calls" 2>/dev/null || echo "(no poll ran)"
if [ -e "$tf" ]; then echo "task reply still staged"; else echo "task reply consumed"; fi
echo "=== firstmate-owned poll with no staged receipt, mode=accept ==="
export MODE=accept; rm -f "$W/calls"
out=$(bin/fm-procevent-lavish.sh poll "$art" 2>&1); echo "exit=$?"; echo "$out"
echo "calls:"; cat "$W/calls"

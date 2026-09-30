#!/usr/bin/env bash
# Behavior tests for the generic process-to-event runner and its Lavish adapter.
#
# The source under test is a fake blocking process that returns only when its
# trigger file appears, so completion is a real process event and no test here
# depends on a discovery timer. The Lavish adapter is exercised through its own
# public commands against the currently published poll shape; no live Lavish
# server is started.
#
# Delivery is deliberately NOT asserted as at-least-once or lossless: the
# published Lavish poll clears feedback destructively before returning it, so
# the only durability under test is the runner's own - output that reached the
# runner is stored before it is announced.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(fm_test_tmproot fm-procevent-tests)
export FM_PROCEVENT_CLAIM_ROOT="$TMP_ROOT/claims"
export LAVISH_AXI_STATE_DIR="$TMP_ROOT/lavish-state"
mkdir -p "$LAVISH_AXI_STATE_DIR"

# Lavish owns this persisted session contract. The fake CLI fixtures exercise
# its published poll and synchronous reply command boundaries without starting a server.
lavish_session() {  # <artifact> [session-url]
  perl -MJSON::PP -MCwd=realpath -MDigest::SHA=sha256_hex -MEncode=decode -e '
    my ($path, $artifact, $url) = @ARGV;
    my $real = realpath($artifact) // die "missing fixture artifact";
    my $key = substr(sha256_hex($real), 0, 16);
    my $state = { sessions => {} };
    if (-f $path) { open my $in, "<", $path or die $!; local $/; $state = decode_json(<$in>); }
    $state->{sessions}{$key} = {
      key => $key, file => decode("UTF-8", $real), status => "open", url => $url,
    };
    open my $out, ">", $path or die $!;
    print $out encode_json($state);
  ' "$LAVISH_AXI_STATE_DIR/state.json" "$1" "${2:-http://127.0.0.1:14387/session/0123456789abcdef}"
}
# A firstmate-owned receipt is best effort: a supported Lavish posts it through
# `reply`, while a refused reply or an unconfirmed version falls back to the
# legacy poll reply and the listener still polls the board.
RECEIPT_POST="$TMP_ROOT/receipt-post"
mkdir -p "$RECEIPT_POST/bin" "$RECEIPT_POST/home/state/procevent"
export RECEIPT_POST
cat > "$RECEIPT_POST/bin/lavish-axi" <<'SH'
#!/usr/bin/env bash
case "${1-}" in
  --version)
    [ "$RECEIPT_POST_MODE" != unknown ] || exit 1
    printf '0.1.80\n' ;;
  reply)
    [ "$RECEIPT_POST_MODE" = accept ] || { printf 'session is gone\n' >&2; exit 1; }
    printf 'reply %s\n' "$(cat -- "$4")" >> "$RECEIPT_POST/calls" ;;
  poll)
    printf 'poll %s\n' "${4-}" >> "$RECEIPT_POST/calls"
    printf 'session:\n  status: ended\n' ;;
  *) exit 2 ;;
esac
SH
chmod +x "$RECEIPT_POST/bin/lavish-axi"
receipt_post_art="$RECEIPT_POST/board.html"
printf '<h1>receipt post</h1>\n' > "$receipt_post_art"
lavish_session "$receipt_post_art"
receipt_post_id=$("$ROOT/bin/fm-procevent-lavish.sh" source-id "$receipt_post_art")
receipt_post_file="$RECEIPT_POST/home/state/procevent/.$receipt_post_id.lavish-receipt"
for mode in accept refuse unknown; do
  rm -f "$RECEIPT_POST/calls"
  printf 'receipt for %s\n' "$mode" > "$receipt_post_file"
  receipt_post_rc=0
  receipt_post_out=$(RECEIPT_POST_MODE=$mode PATH="$RECEIPT_POST/bin:$PATH" FM_HOME="$RECEIPT_POST/home" \
    "$ROOT/bin/fm-procevent-lavish.sh" poll "$receipt_post_art" 2>&1) || receipt_post_rc=$?
  [ "$receipt_post_rc" -eq 0 ] || fail "a $mode receipt post stopped the listener (status $receipt_post_rc): $receipt_post_out"
  assert_contains "$receipt_post_out" 'status: ended' "a $mode receipt post did not print the board's poll response"
  [ ! -e "$receipt_post_file" ] || fail "a $mode receipt post left the receipt staged"
  if [ "$mode" = accept ]; then
    expected=$(printf 'reply receipt for accept\npoll ')
  else
    expected="poll receipt for $mode"
  fi
  [ "$(cat "$RECEIPT_POST/calls")" = "$expected" ] \
    || fail "a $mode receipt post reached the board as: $(cat "$RECEIPT_POST/calls")"
done
pass "a firstmate-owned receipt posts through reply and falls back to the legacy poll reply"

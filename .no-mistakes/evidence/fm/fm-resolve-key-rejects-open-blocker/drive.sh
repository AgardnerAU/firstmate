#!/usr/bin/env bash
# Live driver: real fm-send.sh / fm-wake-drain.sh against a throwaway FM_HOME,
# delivering to a real tmux server on an isolated TMUX_TMPDIR socket.
# Usage: drive.sh <tmproot> <bindir> <label> <scenario>
set -u
T=$1 B=$2 LBL=$3 SC=$4
export TMUX_TMPDIR=$T/tmux
# Sandboxed throwaway fleet: same documented escape hatch tests/lib.sh exports.
export FM_GATE_REFUSE_BYPASS=1
H=$(mktemp -d "$T/home-$LBL-$SC.XXXX"); mkdir -p "$H/state"
printf 'window=sess:fm-t10\nkind=ship\n' > "$H/state/t10.meta"
drain() { echo "\$ bin/fm-wake-drain.sh   # OPEN DECISIONS section"; FM_HOME=$H FM_STATE_OVERRIDE=$H/state "$B/fm-wake-drain.sh" 2>/dev/null | grep -E '^(OPEN DECISIONS|t10 )' || echo "(no OPEN DECISIONS section)"; }
send() { echo "\$ bin/fm-send.sh $(printf '%q ' "$@")"; FM_HOME=$H FM_SEND_SETTLE=0 "$B/fm-send.sh" "$@"; echo "rc=$?"; }
inbox() { echo "--- inbox:"; if [ -d "$H/state/t10.inbox" ]; then for f in "$H/state/t10.inbox"/*.msg; do echo "[$f]"; cat "$f"; echo; done; else echo "(no inbox - nothing delivered)"; fi; }
status() { echo "--- status log:"; cat "$H/state/t10.status"; }
echo "===== [$LBL] scenario $SC  home=$H"
case "$SC" in
reported)
  printf 'blocked: no-mistakes axi run hung without registering a branch run [key=no-mistakes-start]\n' > "$H/state/t10.status"
  status; drain
  send t10 --resolve-key no-mistakes-start 'restart the run'
  inbox ;;
listed-key)
  printf 'blocked: no-mistakes axi run hung without registering a branch run [key=no-mistakes-start]\n' > "$H/state/t10.status"
  line=$(FM_HOME=$H FM_STATE_OVERRIDE=$H/state "$B/fm-wake-drain.sh" 2>/dev/null | grep '^t10 ')
  drain
  key=${line#*\[key=}; key=${key%%]*}
  echo "# operator reads the first [key=...] on the entry: '$key'"
  send t10 --resolve-key "$key" 'restart the run'
  inbox; status; echo "--- after:"; drain ;;
preserve)
  printf 'blocked: axi run hung [key=decoy-token]\nneeds-decision [key=alpha]: A or B\n' > "$H/state/t10.status"
  status; drain
  msg="don't restart it; \$RUN is still live
second line"
  send t10 --resolve-key decoy-token "$msg" 2> "$H/err"; cat "$H/err"
  inbox
  plain=$(grep -F 'deliver without closing anything' "$H/err" | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//')
  echo "# operator pastes the printed plain resend from / with nothing exported:"
  echo "\$ $plain"
  ( cd / && env -u FM_HOME -u FM_STATE_OVERRIDE FM_SEND_SETTLE=0 bash -c "$plain" ); echo "rc=$?"
  inbox; status ;;
multi)
  printf 'needs-decision [key=alpha]: A or B\nneeds-decision [key=beta]: C or D\n' > "$H/state/t10.status"
  status; drain
  send t10 --resolve-key bta --resolve-key alpha 'A, and C' 2> "$H/err"; cat "$H/err"
  inbox
  keyed=$(grep -F -- "--resolve-key '<key>'" "$H/err" | sed 's/^[[:space:]]*//')
  echo "# paste the keyed resend verbatim (placeholder unfilled):"
  ( cd / && env -u FM_HOME -u FM_STATE_OVERRIDE FM_SEND_SETTLE=0 bash -c "$keyed" ); echo "rc=$?"
  inbox
  keyed=${keyed/"'<key>'"/beta}
  echo "# operator fills the placeholder with 'beta' and runs it from /:"
  echo "\$ $keyed"
  ( cd / && env -u FM_HOME -u FM_STATE_OVERRIDE FM_SEND_SETTLE=0 bash -c "$keyed" ); echo "rc=$?"
  inbox; status; echo "--- after:"; drain ;;
held)
  printf 'needs-decision [key=migration]: cut over now or after the freeze\ncaptain-held [key=migration]: transferred to the captain-held task\n' > "$H/state/t10.status"
  status; drain
  send t10 --resolve-key migratoin 'cut over after the freeze'
  inbox ;;
esac

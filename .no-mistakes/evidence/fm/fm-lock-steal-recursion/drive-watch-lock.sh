#!/usr/bin/env bash
# Live driver: run the real bin/fm-watch.sh in a disposable lab FM_HOME.
# Usage: drive-watch-lock.sh <repo-root-with-bin> <scenario: normal|refuse|release>
set -u
ROOT=$1; SC=$2
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$PWD/bin/fm-lab-home.sh" create "$LAB" >/dev/null
SHIM="$LAB/shim"; mkdir -p "$SHIM"
REAL_MKTEMP=$(command -v mktemp); REAL_RMDIR=$(command -v rmdir)
LOCK="$LAB/state/.watch.lock"
run() { env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" "$@"; }
echo "== scenario=$SC root=$ROOT lab=$LAB"
case "$SC" in
  normal)
    run "$ROOT/bin/fm-watch.sh" >"$LAB/w1.out" 2>&1 &
    W=$!
    for i in $(seq 1 100); do [ -e "$LOCK/pid" ] && break; sleep 0.1; done
    echo "first watcher pid=$W lock pid=$(cat "$LOCK/pid" 2>/dev/null)"
    echo "-- second start:"; run "$ROOT/bin/fm-watch.sh" 2>&1; echo "second rc=$?"
    kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
    ;;
  refuse)
    cat > "$SHIM/mktemp" <<SH
#!/usr/bin/env bash
case "\$*" in *.watch.lock*.owner.*) a="\$*"; d=0; while [ "\${a#*.steal}" != "\$a" ]; do a=\${a#*.steal}; d=\$((d+1)); done; printf "%s\n" "\$d" >> "$LAB/refused"; exit 1;; esac
exec $REAL_MKTEMP "\$@"
SH
    chmod +x "$SHIM/mktemp"
    start=$(date +%s)
    PATH="$SHIM:$PATH" run perl -e 'alarm 30; exec @ARGV' "$ROOT/bin/fm-watch.sh" >"$LAB/w.out" 2>&1; rc=$?
    echo "fm-watch rc=$rc elapsed=$(( $(date +%s)-start ))s"
    echo "-- fm-watch output (first 5 lines, each cut to 200 chars):"; head -5 "$LAB/w.out" | cut -c1-200
    echo "refused lock creations: $(wc -l < "$LAB/refused" 2>/dev/null || echo 0); deepest reclaim-marker depth attempted: $(sort -n "$LAB/refused" 2>/dev/null | tail -1)"
    echo "'File name too long' lines: $(grep -c 'File name too long' "$LAB/w.out")"
    echo "reclaim markers left in state: $(ls -a "$LAB/state" | grep -c '\.steal')"
    ;;
  release)
    dead=99999; while kill -0 $dead 2>/dev/null; do dead=$((dead+1)); done
    OWNER="$LOCK.owner.crashed"; mkdir "$OWNER"; echo $dead > "$OWNER/pid"; ln -s "$OWNER" "$LOCK"
    cat > "$SHIM/rmdir" <<SH
#!/usr/bin/env bash
if [ ! -e "$LAB/released" ] && [ "\$*" != "$OWNER" ]; then
  case "\$*" in *.watch.lock.owner.*) rm -f "$LOCK" "$OWNER/pid"; $REAL_RMDIR "$OWNER" 2>/dev/null; : > "$LAB/released";; esac
fi
exec $REAL_RMDIR "\$@"
SH
    chmod +x "$SHIM/rmdir"
    PATH="$SHIM:$PATH" run "$ROOT/bin/fm-watch.sh" >"$LAB/w.out" 2>&1 &
    W=$!
    for i in $(seq 1 100); do p=$(cat "$LOCK/pid" 2>/dev/null); [ -n "$p" ] && [ "$p" != "$dead" ] && break; kill -0 $W 2>/dev/null || break; sleep 0.1; done
    echo "release fired: $([ -e "$LAB/released" ] && echo yes || echo no)"
    echo "watcher pid=$W alive=$(kill -0 $W 2>/dev/null && echo yes || echo no) lock pid=$(cat "$LOCK/pid" 2>/dev/null)"
    echo "-- fm-watch output:"; head -5 "$LAB/w.out" | cut -c1-200
    kill "$W" 2>/dev/null; wait "$W" 2>/dev/null
    ;;
esac
pkill -f "$LAB" 2>/dev/null
rm -rf "$LAB"; echo "lab removed: $([ -e "$LAB" ] && echo no || echo yes)"

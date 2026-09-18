#!/usr/bin/env bash
# Full-chain drive: a real no-mistakes run record -> the REAL bin/fm-crew-state.sh
# reader -> bin/fm-inactive-reconcile.sh -> the captain-facing terminal outcome
# record and wake payload. No stubbed reader: only the external `no-mistakes`
# CLI and the terminal multiplexer are faked.
set -u
ROOT=${ROOT:-$PWD}
RECON="$ROOT/bin/fm-inactive-reconcile.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-captain-drive.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=fmtest GIT_AUTHOR_EMAIL=fmtest@example.invalid
export GIT_COMMITTER_NAME=fmtest GIT_COMMITTER_EMAIL=fmtest@example.invalid

set_mtime() { local e=$1 p=$2 s; s=$(date -r "$e" +%Y%m%d%H%M.%S 2>/dev/null) || s=$(date -d "@$e" +%Y%m%d%H%M.%S); touch -t "$s" "$p"; }
age() { local now; now=$(( $(date +%s) - 600 )); for p in "$@"; do set_mtime "$now" "$p"; done; }
stamp_minutes_ago() { local e; e=$(( $(date +%s) - $1 * 60 )); date -r "$e" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$e" '+%Y-%m-%d %H:%M'; }

make_world() {  # <name> <branch>
  WORLD="$TMP/$1"; MAIN="$WORLD/main"
  mkdir -p "$WORLD/root" "$MAIN"/{state,data,config,projects}
  FB="$WORLD/fakebin"; mkdir -p "$FB"
  cat > "$FB/no-mistakes" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  axi) shift
    if [ "$#" = 0 ]; then printf '%s\n' "${FM_FAKE_AXI_STATUS:-}"; exit 0; fi
    case "${1:-}" in
      status) shift; if [ "${1:-}" = --run ]; then printf '%s\n' "${FM_FAKE_AXI_STATUS_RUN:-}"; else printf '%s\n' "${FM_FAKE_AXI_STATUS:-}"; fi ;;
      logs) printf '\n' ;;
    esac ;;
  runs) printf '%s\n' "${FM_FAKE_RUNS_LIST:-}" ;;
  daemon) printf 'daemon running (pid 4242)\n'; exit 0 ;;
esac
exit 0
SH
  cat > "$FB/tmux" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  display-message) printf '%%1\n' ;;
  capture-pane) printf 'idle\n> \n' ;;
esac
SH
  for t in gh gh-axi curl; do printf '#!/usr/bin/env bash\nexit 97\n' > "$FB/$t"; done
  chmod +x "$FB"/*
  WT="$MAIN/projects/child"; mkdir -p "$WT"
  git -C "$WT" init -q; git -C "$WT" commit -q --allow-empty -m init
  git -C "$WT" checkout -q -b "$2"
  HEAD_SHA=$(git -C "$WT" rev-parse HEAD); SHORT=$(git -C "$WT" rev-parse --short=8 HEAD)
  printf 'window=firstmate:fm-child\nworktree=%s\nproject=alpha\nharness=codex\nkind=ship\nmode=no-mistakes\nyolo=off\nspawn_gen=s1.1\npr=https://example.test/owner/repo/pull/1\n' "$WT" > "$MAIN/state/child.meta"
  printf 'working: still validating\n' > "$MAIN/state/child.status"
  : > "$MAIN/state/child.turn-ended"
  age "$MAIN/state/child.meta" "$MAIN/state/child.status" "$MAIN/state/child.turn-ended"
}
reader() { PATH="$FB:$PATH" FM_STATE_OVERRIDE="$MAIN/state" FM_CREW_STATE_NO_FORGE=1 "$ROOT/bin/fm-crew-state.sh" child; }
reconcile() {
  PATH="$FB:$PATH" FM_ROOT_OVERRIDE="$WORLD/root" FM_HOME="$MAIN" \
    FM_STATE_OVERRIDE="$MAIN/state" FM_DATA_OVERRIDE="$MAIN/data" FM_CONFIG_OVERRIDE="$MAIN/config" \
    FM_INACTIVE_RECONCILE_SECS=60 FM_INACTIVE_CREW_STATE_BIN="$ROOT/bin/fm-crew-state.sh" \
    FM_CREW_STATE_NO_FORGE=1 FM_FORGE_LOG="$WORLD/forge.log" "$RECON" scan --startup
}
report() {
  printf '\nreader line  -> %s\n' "$(reader)"
  reconcile >/dev/null 2>&1 || true
  printf 'captain wake -> %s\n' "$(grep -F 'inactive-outcome:' "$MAIN/state/.wake-queue" 2>/dev/null | tail -1 || true)"
  printf 'outcome record ->\n'
  local f found=0
  for f in "$MAIN"/state/terminal-outcomes/*; do
    [ -f "$f" ] || continue; found=1
    printf '  [%s]\n' "$(basename "$f")"; sed 's/^/    /' "$f"
  done
  [ "$found" = 1 ] || printf '  <none: nothing promoted to the captain>\n'
}
hdr() { printf '\n================================================================\nCASE: %s\n----------------------------------------------------------------\n' "$1"; }

hdr "E1 stale failed run at this head while a newer run is in flight"
make_world e1 fm/feat-e1
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-e1
  status: failed
  head: \"$HEAD_SHA\"
  pr: \"https://example.test/owner/repo/pull/1\"
  findings: none
outcome: failed"
export FM_FAKE_RUNS_LIST="  running    fm/feat-e1 f0f0f0f0  $(stamp_minutes_ago 10)
  failed     fm/feat-e1 ${SHORT}  $(stamp_minutes_ago 90)"
printf 'ledger:\n%s\n' "$FM_FAKE_RUNS_LIST"
report

hdr "E2 genuine failure, nothing newer on the branch (must still reach the captain)"
make_world e2 fm/feat-e2
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-e2
  status: failed
  head: \"$HEAD_SHA\"
  pr: \"\"
  findings: none
outcome: failed"
export FM_FAKE_RUNS_LIST="  failed     fm/feat-e2 ${SHORT}  $(stamp_minutes_ago 90)"
printf 'ledger:\n%s\n' "$FM_FAKE_RUNS_LIST"
report

hdr "E3 delivered work: the captain is told the run's OWN pull request, not the task meta's old one"
make_world e3 fm/feat-e3
export FM_FAKE_AXI_STATUS="run:
  id: \"01RUN\"
  branch: fm/feat-e3
  status: completed
  head: \"$HEAD_SHA\"
  pr: \"https://example.test/owner/repo/pull/2222\"
  findings: none
outcome: passed"
export FM_FAKE_RUNS_LIST=""
printf 'ledger: <no row for this branch in the window>\ntask meta records pr=https://example.test/owner/repo/pull/1\n'
report
printf '\n'

#!/usr/bin/env bash
# Operator-style driver: stands up a throwaway firstmate home + real git crew
# worktree + a fake `no-mistakes` CLI, then runs the REAL bin/fm-crew-state.sh
# and bin/fm-inactive-reconcile.sh the way firstmate runs them.
set -u
SRC=${SRC:?set SRC to the firstmate checkout}
W=${W:?set W to a throwaway world dir}
rm -rf "$W"; mkdir -p "$W"
export GIT_CONFIG_GLOBAL=$W/gitconfig GIT_CONFIG_SYSTEM=/dev/null
git config --global user.name fmdrive; git config --global user.email fmdrive@example.invalid
git config --global init.defaultBranch main

mk_fakebin() {
  local fb=$W/fakebin; mkdir -p "$fb"
  cat > "$fb/no-mistakes" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  axi) shift
    if [ "$#" = 0 ]; then printf '%s\n' "${FM_FAKE_AXI_STATUS:-}"; exit 0; fi
    case "${1:-}" in
      status) shift
        if [ "${1:-}" = --run ]; then printf '%s\n' "${FM_FAKE_AXI_STATUS:-}"; else printf '%s\n' "${FM_FAKE_AXI_STATUS:-}"; fi ;;
      logs) printf '%s\n' "${FM_FAKE_CI_LOGS:-}" ;;
    esac ;;
  runs) printf '%s\n' "${FM_FAKE_RUNS_LIST:-}" ;;
  daemon) printf 'daemon running (pid 4242)\n'; exit 0 ;;
esac
exit 0
SH
  cat > "$fb/tmux" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  display-message) printf '%%1\n' ;;
  capture-pane) printf 'all quiet\n> \n' ;;
esac
exit 0
SH
  for t in gh gh-axi curl glab; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$(basename "$0")" >> "${FM_FORGE_LOG:-/dev/null}"\nexit 97\n' > "$fb/$t"
  done
  chmod +x "$fb"/*
}

new_crew() { # <id> <branch> [kind]
  local id=$1 branch=$2 kind=${3:-ship}
  local wt=$W/home/projects/$id
  mkdir -p "$wt" "$W/home/state" "$W/home/data" "$W/home/config" "$W/root"
  git -C "$wt" init -q
  git -C "$wt" commit -q --allow-empty -m init
  git -C "$wt" checkout -q -b "$branch"
  HEAD_FULL=$(git -C "$wt" rev-parse HEAD); HEAD_SHORT=$(git -C "$wt" rev-parse --short=8 HEAD)
  {
    printf 'window=firstmate:fm-%s\n' "$id"
    printf 'worktree=%s\n' "$wt"
    printf 'project=alpha\nharness=codex\nkind=%s\nmode=no-mistakes\nyolo=off\n' "$kind"
    printf 'spawn_gen=s1.1\n'
    printf 'pr=https://example.test/owner/repo/pull/1\n'
  } > "$W/home/state/$id.meta"
}

crew_state() { # <id>
  PATH="$W/fakebin:$PATH" FM_STATE_OVERRIDE="$W/home/state" FM_CREW_STATE_NO_FORGE=1 \
    "$SRC/bin/fm-crew-state.sh" "$1"
}

reconcile() {
  : > "$W/forge.log"
  PATH="$W/fakebin:$PATH" FM_ROOT_OVERRIDE="$W/root" FM_HOME="$W/home" \
    FM_STATE_OVERRIDE="$W/home/state" FM_DATA_OVERRIDE="$W/home/data" \
    FM_CONFIG_OVERRIDE="$W/home/config" FM_INACTIVE_RECONCILE_SECS=60 \
    FM_FORGE_LOG="$W/forge.log" FM_CREW_STATE_NO_FORGE=1 \
    "$SRC/bin/fm-inactive-reconcile.sh" scan --startup
}

age_files() { local now; now=$(( $(date +%s) - 600 )); local s; s=$(date -r "$now" +%Y%m%d%H%M.%S); touch -t "$s" "$@"; }

run_failed_with_pr() { # <branch> <pr>
  printf 'run:\n  id: "01RUN"\n  branch: %s\n  status: failed\n  head: "%s"\n  pr: "%s"\n  findings: none\n  steps[2]{step,status,findings,duration_ms}:\n    intent,completed,0,0\n    review,failed,1,0\n' "$1" "$HEAD_FULL" "$2"
}
run_failed() { printf 'run:\n  id: "01RUN"\n  branch: %s\n  status: failed\n  head: "%s"\n  pr: ""\n  findings: none\n  steps[2]{step,status,findings,duration_ms}:\n    intent,completed,0,0\n    review,failed,1,0\n' "$1"; }
stamp_ago() { local m=$1 now; now=$(( $(date +%s) - m*60 )); date -r "$now" '+%Y-%m-%d %H:%M'; }

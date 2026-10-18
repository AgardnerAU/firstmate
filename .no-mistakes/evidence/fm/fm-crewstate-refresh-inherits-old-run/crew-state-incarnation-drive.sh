#!/usr/bin/env bash
# Manual drive: real bin/fm-crew-state.sh against a disposable lab FM_HOME, a real
# git worktree on a reused branch, and a stub no-mistakes CLI serving one run.
set -u
ROOT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
trap 'rm -rf "$LAB"' EXIT
WT=$LAB/wt; mkdir -p "$WT"
git -C "$WT" init -q; git -C "$WT" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$WT" checkout -q -b fm/refresh
git -C "$WT" update-ref refs/remotes/origin/main "$(git -C "$WT" rev-parse HEAD)"
HEAD_FULL=$(git -C "$WT" rev-parse HEAD); SHORT=$(git -C "$WT" rev-parse --short=8 HEAD)
FB=$LAB/fakebin; mkdir -p "$FB"
cat > "$FB/no-mistakes" <<'SH'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "axi ") printf '%s\n' "$NM_HOME_OUT" ;;
  "axi status") printf '%s\n' "$NM_STATUS" ;;
  "runs "*) printf '%s\n' "${NM_RUNS:-}" ;;
  "daemon "*) echo "  ● daemon running (pid 4242)" ;;
esac
exit 0
SH
chmod +x "$FB/no-mistakes"
ulid_at() { local ms=$(($1*1000)) a=0123456789ABCDEFGHJKMNPQRSTVWXYZ t='' i; for i in 1 2 3 4 5 6 7 8 9 10; do t="${a:$((ms%32)):1}$t"; ms=$((ms/32)); done; printf '%sABCDEFGHJKMNPQRS' "$t"; }
drive() {  # <label> <run-epoch> <meta-line>
  local id; id=$(ulid_at "$2")
  printf 'window=fm:fm-refresh\nworktree=%s\nkind=ship\nharness=claude\n%s\n' "$WT" "$3" > "$LAB/state/refresh.meta"
  export NM_STATUS="run:
  id: \"$id\"
  branch: fm/refresh
  status: completed
  head: \"$HEAD_FULL\"
  pr: \"\"
  findings: none
outcome: passed"
  export NM_HOME_OUT="count: 1 of 1 total
runs[1]{id,branch,status,head,pr}:
  \"$id\",fm/refresh,completed,$SHORT,\"\""
  echo "### $1"
  echo "meta: $3 ; run id $id created at epoch $2"
  echo "\$ FM_HOME=\$LAB bin/fm-crew-state.sh refresh"
  env -u FM_STATE_OVERRIDE -u FM_ROOT_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
    PATH="$FB:$PATH" FM_HOME="$LAB" "$ROOT/bin/fm-crew-state.sh" refresh
  echo
}
NOW=$(date +%s)
printf 'working [at=%s]: resolving merge conflicts after merging upstream main\n' "$NOW" > "$LAB/state/refresh.status"
drive "A. refresh task, earlier task's passed run on same branch+head (1h before task start)" $((NOW-3600)) "task_started=$NOW"
drive "B. same task, its own run created after task start" $((NOW+5)) "task_started=$NOW"
drive "C. legacy record without task_started: spawn_gen epoch bounds it" $((NOW-3600)) "spawn_gen=s$NOW.1.1"
drive "D. control: no start record at all (pre-change behaviour, unbounded)" $((NOW-3600)) "x=1"

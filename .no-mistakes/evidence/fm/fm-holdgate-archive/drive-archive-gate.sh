#!/usr/bin/env bash
# Manual end-to-end drive of the captain-hold completion gate against a real
# tasks-axi backlog and a real `tasks-axi prune` archive.
set -u
ROOT=/Users/agardner/.no-mistakes/worktrees/c272d8f3fc4c/01M2TNESBHX3ZAAWT5WJZM3YVY
HOLD="$ROOT/bin/fm-captain-hold.sh"
TEARDOWN="$ROOT/bin/fm-teardown.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/holdgate.XXXXXX")
TASKS_AXI_BIN=$(command -v tasks-axi)

make_home() {
  local home="$TMP/$1"
  mkdir -p "$home/data" "$home/state" "$home/config" "$home/projects" "$home/fakebin"
  cp "$ROOT/.tasks.toml" "$home/.tasks.toml"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
  for b in tmux treehouse no-mistakes gh gh-axi; do
    printf '#!/bin/sh\nexit 0\n' > "$home/fakebin/$b"; chmod +x "$home/fakebin/$b"
  done
  printf '%s\n' "$home"
}
captain() { local h=$1; shift; PATH="$h/fakebin:$PATH" REAL_TASKS_AXI="$TASKS_AXI_BIN" \
  FM_HOME="$h" FM_STATE_OVERRIDE="$h/state" FM_DATA_OVERRIDE="$h/data" \
  FM_CONFIG_OVERRIDE="$h/config" "$HOLD" "$@"; }
teardown() { local h=$1; shift; PATH="$h/fakebin:$PATH" FM_GATE_REFUSE_BYPASS=1 FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$h" \
  FM_STATE_OVERRIDE="$h/state" FM_DATA_OVERRIDE="$h/data" FM_CONFIG_OVERRIDE="$h/config" "$TEARDOWN" "$@"; }
tasks() { local h=$1; shift; (cd "$h" && tasks-axi "$@"); }
meta() { local h=$1 id=$2; printf 'window=firstmate:fm-%s\nworktree=%s/projects/missing-%s\nproject=%s/projects/sample\nharness=codex\nkind=scout\nmode=scout\nspawn_gen=fixture-%s\n' "$id" "$h" "$id" "$h" "$id" > "$h/state/$id.meta"; }

setup_origin() { # home origin call
  local h=$1 o=$2 c=$3
  mkdir -p "$h/data/$o"
  tasks "$h" add "$o" "Review $o" --kind scout --repo sample --start >/dev/null
  meta "$h" "$o"
  printf 'done: report complete\n' > "$h/state/$o.status"
  printf '# %s\n\nOne captain choice remained.\n' "$o" > "$h/data/$o/report.md"
  captain "$h" hold "$c" --title "Choose for $o" --reason "captain choice pending" --repo sample >/dev/null
  captain "$h" complete "$o" "$c" >/dev/null
}

hr() { printf '\n========== %s ==========\n' "$1"; }

HOME_A=$(make_home scenario)
hr "SCENARIO 1 setup: answered captain call, then archived by a real tasks-axi prune"
setup_origin "$HOME_A" sample-answered-review sample-answered-call
printf 'Take the northern route.\n' > "$HOME_A/answer.txt"
captain "$HOME_A" answer sample-answered-call --decision-file "$HOME_A/answer.txt" >/dev/null
echo "\$ tasks-axi prune --keep 0 --state done"
tasks "$HOME_A" prune --keep 0 --state "done"
echo "\$ tasks-axi show sample-answered-call   # live backlog"
tasks "$HOME_A" show sample-answered-call; echo "exit=$?"
echo "--- data/done-archive.md (head) ---"; sed -n '1,12p' "$HOME_A/data/done-archive.md"

hr "SCENARIO 1: verify + complete + teardown on the answered, archived call"
echo "\$ fm-captain-hold.sh verify sample-answered-review"
captain "$HOME_A" verify sample-answered-review; echo "exit=$?"
echo "\$ fm-captain-hold.sh complete sample-answered-review sample-answered-call"
captain "$HOME_A" complete sample-answered-review sample-answered-call; echo "exit=$?"
echo "\$ fm-teardown.sh sample-answered-review"
teardown "$HOME_A" sample-answered-review; echo "exit=$?"

hr "SCENARIO 2: unanswered call, closed bare and archived - gate must still refuse"
setup_origin "$HOME_A" sample-dropped-review sample-dropped-call
tasks "$HOME_A" "done" sample-dropped-call >/dev/null
tasks "$HOME_A" prune --keep 0 --state "done" >/dev/null
grep -c 'sample-dropped-call' "$HOME_A/data/done-archive.md" | sed 's/^/archived rows for the dropped call: /'
echo "\$ fm-captain-hold.sh verify sample-dropped-review"
captain "$HOME_A" verify sample-dropped-review; echo "exit=$?"
echo "\$ fm-teardown.sh sample-dropped-review"
teardown "$HOME_A" sample-dropped-review; echo "exit=$?"
echo "origin row survives teardown refusal:"; tasks "$HOME_A" show sample-dropped-review | head -3

hr "SCENARIO 3: reused id - old answered archived row must not wave through a new unanswered one"
HOME_B=$(make_home reused)
setup_origin "$HOME_B" sample-first-review sample-reused-call
printf 'Answered the first time.\n' > "$HOME_B/answer.txt"
captain "$HOME_B" answer sample-reused-call --decision-file "$HOME_B/answer.txt" >/dev/null
tasks "$HOME_B" prune --keep 0 --state "done" >/dev/null
setup_origin "$HOME_B" sample-second-review sample-reused-call
tasks "$HOME_B" "done" sample-reused-call >/dev/null
tasks "$HOME_B" prune --keep 0 --state "done" >/dev/null
echo "archive sections:"; grep -n '^## ' "$HOME_B/data/done-archive.md"
echo "\$ tasks-axi show sample-reused-call --file data/done-archive.md  # backend returns the FIRST (stale, answered) row"
(cd "$HOME_B" && tasks-axi show sample-reused-call --file data/done-archive.md --full 2>&1 | head -12)
echo "\$ fm-captain-hold.sh verify sample-second-review   # must refuse - this call was never answered"
captain "$HOME_B" verify sample-second-review; echo "exit=$?"
echo "(both reviews inventory the SAME reused id, so the newest row governs both - the first review now refuses too, which is the conservative direction)"

hr "SCENARIO 4: unreadable archive must refuse by name, absent archive must not"
HOME_C=$(make_home unreadable)
setup_origin "$HOME_C" sample-unreadable-review sample-unreadable-call
printf 'Southern route.\n' > "$HOME_C/answer.txt"
captain "$HOME_C" answer sample-unreadable-call --decision-file "$HOME_C/answer.txt" >/dev/null
tasks "$HOME_C" prune --keep 0 --state "done" >/dev/null
echo "\$ verify with a readable archive"; captain "$HOME_C" verify sample-unreadable-review; echo "exit=$?"
chmod 000 "$HOME_C/data/done-archive.md"
echo "\$ verify with a mode-000 archive"; captain "$HOME_C" verify sample-unreadable-review; echo "exit=$?"
chmod 644 "$HOME_C/data/done-archive.md"
HOME_D=$(make_home noarchive)
setup_origin "$HOME_D" sample-live-review sample-live-call
printf 'Still live.\n' > "$HOME_D/answer.txt"
captain "$HOME_D" answer sample-live-call --decision-file "$HOME_D/answer.txt" >/dev/null
echo "archive file exists? $( [ -e "$HOME_D/data/done-archive.md" ] && echo yes || echo no )"
echo "\$ verify with no archive at all (answer still live)"; captain "$HOME_D" verify sample-live-review; echo "exit=$?"

hr "SCENARIO 5: configured [markdown] archive path is honoured; decoy keys ignored"
HOME_E=$(make_home configured)
cat > "$HOME_E/.tasks.toml" <<'TOML'
archive = "data/decoy-root.md"

[other]
archive = "data/decoy-other.md"

[markdown]
path = "data/backlog.md"
archive = 'data/closed#1.md'  # single-quoted with a hash inside and a comment
TOML
setup_origin "$HOME_E" sample-configured-review sample-configured-call
printf 'Configured route.\n' > "$HOME_E/answer.txt"
captain "$HOME_E" answer sample-configured-call --decision-file "$HOME_E/answer.txt" >/dev/null
tasks "$HOME_E" prune --keep 0 --state "done" >/dev/null
echo "files in data/: "; ls "$HOME_E/data"
echo "\$ fm-captain-hold.sh verify sample-configured-review"
captain "$HOME_E" verify sample-configured-review; echo "exit=$?"
echo "\$ fm-teardown.sh sample-configured-review"
teardown "$HOME_E" sample-configured-review; echo "exit=$?"

hr "SCENARIO 6: a wedged archive read stops the gate by name instead of hanging"
HOME_F=$(make_home wedged)
setup_origin "$HOME_F" sample-wedged-review sample-wedged-call
printf 'Wedge route.\n' > "$HOME_F/answer.txt"
captain "$HOME_F" answer sample-wedged-call --decision-file "$HOME_F/answer.txt" >/dev/null
tasks "$HOME_F" prune --keep 0 --state "done" >/dev/null
cat > "$HOME_F/fakebin/tasks-axi" <<WEDGE
#!/bin/sh
for a in "\$@"; do
  case "\$a" in *done-archive*|*fm-captain-hold-archive*) sleep 120 ;; esac
done
exec "$TASKS_AXI_BIN" "\$@"
WEDGE
chmod +x "$HOME_F/fakebin/tasks-axi"
echo "\$ FM_BACKLOG_ROW_TIMEOUT_SECS=2 fm-captain-hold.sh verify sample-wedged-review"
start=$(date +%s)
PATH="$HOME_F/fakebin:$PATH" REAL_TASKS_AXI="$TASKS_AXI_BIN" FM_BACKLOG_ROW_TIMEOUT_SECS=2 \
  FM_HOME="$HOME_F" FM_STATE_OVERRIDE="$HOME_F/state" FM_DATA_OVERRIDE="$HOME_F/data" \
  FM_CONFIG_OVERRIDE="$HOME_F/config" "$HOLD" verify sample-wedged-review; rc=$?
echo "exit=$rc after $(( $(date +%s) - start ))s"

echo
echo "fixture root: $TMP"

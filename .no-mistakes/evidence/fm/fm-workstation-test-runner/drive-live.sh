#!/usr/bin/env bash
# Live driver for bin/fm-remote-verify.sh against runner@llm-box.
# Builds a disposable lab under $TMPDIR (outside the run worktree).
set -u
WT=/Users/agardner/.no-mistakes/worktrees/c272d8f3fc4c/01M4FZAFXHJT622S2940RN9C1Y
EV=/Users/agardner/.no-mistakes/evidence/01M4FZAFXHJT622S2940RN9C1Y
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-rv-lab.XXXXXX")
echo "lab=$LAB"
mkdir -p "$LAB/cfg-empty" "$LAB/cfg-bad" "$LAB/cfg-unreach" "$LAB/cfg-live"
gc() { git -c user.name=T -c user.email=t@e.test "$@"; }
git -C "$LAB" init -q repo
cd "$LAB/repo" || exit 1
printf 'one\n' > kept.txt; printf 'gone\n' > deleted.txt; printf 'MODE=t\n' > .env.test
git add . && gc commit -qm first
printf 'two\n' >> kept.txt; gc commit -qam second
git config --local credential.helper store
git remote add origin https://github.com/example/never-used.git
mkdir -p "$(git rev-parse --git-dir)/hooks"
printf '#!/bin/sh\nexit 0\n' > "$(git rev-parse --git-dir)/hooks/pre-commit"
chmod +x "$(git rev-parse --git-dir)/hooks/pre-commit"
git worktree add -qb v "$LAB/tree"
cd "$LAB/tree" || exit 1
rm deleted.txt
printf 'SECRET=x\n' > .env
printf 'K\n' > id_rsa
printf 'new\n' > untracked.txt
cp "$EV/probe.sh" probe.sh
printf 'echo failing on purpose; exit 7\n' > fail.sh
echo "local head=$(git rev-parse HEAD) local remotes=[$(git remote)] local credential.helper=[$(git config --get credential.helper)]"

run() { echo "\$ $*"; "$@"; echo "exit=$?"; echo; }

{
  echo '# S1 missing config'
  FM_CONFIG_OVERRIDE="$LAB/cfg-empty" run "$WT/bin/fm-remote-verify.sh" "$LAB/tree" true
  printf 'not a destination\n' > "$LAB/cfg-bad/remote-verify"
  echo '# S2 malformed config ("not a destination")'
  FM_CONFIG_OVERRIDE="$LAB/cfg-bad" run "$WT/bin/fm-remote-verify.sh" "$LAB/tree" true
  printf 'runner@no-such-host.invalid\n' > "$LAB/cfg-unreach/remote-verify"
  echo '# S3 unreachable host'
  FM_CONFIG_OVERRIDE="$LAB/cfg-unreach" run "$WT/bin/fm-remote-verify.sh" "$LAB/tree" true
  echo '# S3b path is not a worktree root'
  printf 'runner@llm-box\n' > "$LAB/cfg-live/remote-verify"
  FM_CONFIG_OVERRIDE="$LAB/cfg-live" run "$WT/bin/fm-remote-verify.sh" "$LAB" true
} > "$EV/live-refusals.txt" 2>&1

{
  echo '# S4 live run on runner@llm-box: history, Git boundary, file selection, GPU env'
  FM_CONFIG_OVERRIDE="$LAB/cfg-live" run "$WT/bin/fm-remote-verify.sh" "$LAB/tree" bash probe.sh
} > "$EV/live-probe.txt" 2>&1

{
  echo '# S5 remote failure exit code passes through unchanged'
  FM_CONFIG_OVERRIDE="$LAB/cfg-live" run "$WT/bin/fm-remote-verify.sh" "$LAB/tree" bash fail.sh
  echo '# S5b argv is not evaluated as shell text'
  FM_CONFIG_OVERRIDE="$LAB/cfg-live" run "$WT/bin/fm-remote-verify.sh" "$LAB/tree" printf '[%s]\n' '$(hostname); echo injected' 'a b'
} > "$EV/live-exit.txt" 2>&1

hash=$(printf %s "$(cd "$LAB/tree" && pwd -P)" | shasum -a 256 | cut -c1-16)
{
  echo '# S6 remote task directory after runs (expected empty)'
  ssh -o BatchMode=yes runner@llm-box "ls -A ~/.cache/firstmate/verify/$hash/ | sed 's/^/  /'; echo count=\$(ls -A ~/.cache/firstmate/verify/$hash/ | wc -l)"
  echo '# S6b local lab worktree status (only the files the test created)'
  git -C "$LAB/tree" status --porcelain
} > "$EV/live-cleanup.txt" 2>&1

echo "$LAB" > "$EV/lab-path.txt"

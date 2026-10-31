#!/usr/bin/env bash
# Live drive of bin/fm-update.sh from a real clone of the change under test,
# against a disposable lab FM_HOME and local bare origin/fork remotes.
set -u
WT=$1
S=$(mktemp -d "${TMPDIR:-/tmp}/fm-upd-live.XXXXXX")
trap 'rm -rf "$S"' EXIT
g() { git -c user.name=lab -c user.email=lab@example.invalid "$@"; }

world() {  # <name>  -> builds $S/<name>/{seed,origin.git,fork.git,primary,sm1,sm2,lab}
  local w="$S/$1"
  mkdir -p "$w"
  g clone -q "$WT" "$w/seed"; g -C "$w/seed" checkout -q -B main HEAD
  g init -q --bare -b main "$w/origin.git"; g -C "$w/seed" push -q "$w/origin.git" main
  g -C "$w/seed" remote remove origin; g -C "$w/seed" remote add origin "$w/origin.git"
  g clone -q "$w/origin.git" "$w/primary"
  g -C "$w/primary" remote set-head origin main >/dev/null 2>&1
  "$WT/bin/fm-lab-home.sh" create "$w/lab" >/dev/null
  # standalone-clone secondmate and linked-worktree secondmate, registry only
  g clone -q "$w/origin.git" "$w/sm2"; g -C "$w/sm2" remote set-head origin main >/dev/null 2>&1
  printf 'sm2\n' > "$w/sm2/.fm-secondmate-home"
  g -C "$w/primary" worktree add -q --detach "$w/sm1" main
  printf 'sm1\n' > "$w/sm1/.fm-secondmate-home"
  {
    printf -- '- sm1 - lab linked (home: %s/sm1; scope: lab; projects: p; added 2026-10-31)\n' "$w"
    printf -- '- sm2 - lab standalone (home: %s/sm2; scope: lab; projects: p; added 2026-10-31)\n' "$w"
  } > "$w/lab/data/secondmates.md"
}
carry() {  # <w> -> fork.git with carry = main + carried AGENTS.md change; echoes sha
  local w="$S/$1"
  g init -q --bare "$w/fork.git"
  g -C "$w/seed" checkout -q -b carry-work main
  printf '\n<!-- carried lab fix -->\n' >> "$w/seed/AGENTS.md"
  g -C "$w/seed" commit -qam "carried fix"
  g -C "$w/seed" push -q "$w/fork.git" carry-work:carry
  g -C "$w/seed" rev-parse HEAD
  g -C "$w/seed" checkout -q main
  g -C "$w/primary" remote add fork "$w/fork.git"
}
bump_origin() {
  local w="$S/$1"
  printf 'origin-only lab bump\n' >> "$w/seed/README.md"
  g -C "$w/seed" commit -qam "origin bump"; g -C "$w/seed" push -q "$w/origin.git" main
  g -C "$w/seed" rev-parse HEAD
}
run() {  # <w>
  local w="$S/$1"
  ( cd "$w/primary" && env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE \
      -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u TMUX \
      TMUX_TMPDIR="$w/lab" FM_HOME="$w/lab" bin/fm-update.sh; echo "[exit=$?]" )
}
heads() { local w="$S/$1"; for r in primary sm1 sm2; do printf '  %s HEAD=%s\n' "$r" "$(git -C "$w/$r" rev-parse --short HEAD)"; done; }
short() { git -C "$S/$1/seed" rev-parse --short "$2"; }

echo "=== S1: config/self-update-source 'fork carry' -> primary and local secondmates follow the fork branch, not origin ==="
world s1; C=$(carry s1); O=$(bump_origin s1)
echo "carry=$(short s1 "$C") origin-tip=$(short s1 "$O") start=$(git -C "$S/s1/primary" rev-parse --short HEAD)"
printf 'fork carry\n' > "$S/s1/lab/config/self-update-source"
run s1; heads s1
echo "--- S1b: remove the file -> origin path is used again, diverged primary is left alone ---"
rm "$S/s1/lab/config/self-update-source"
run s1; heads s1

echo; echo "=== S2: no config file -> unchanged origin behaviour (fast-forward to origin) ==="
world s2; C=$(carry s2); O=$(bump_origin s2)
echo "carry=$(short s2 "$C") origin-tip=$(short s2 "$O")"
run s2; heads s2

echo; echo "=== S3: unusable config files refuse before anything moves, never falling back to origin ==="
world s3; carry s3 >/dev/null; O=$(bump_origin s3); echo "origin-tip=$(short s3 "$O")"
for v in "nosuchremote carry" "fork" "fork carry extra" "fork bad..branch" "-x carry" "fork -carry" $'fork carry\nfork other'; do
  printf '%s\n' "$v" > "$S/s3/lab/config/self-update-source"
  echo "--- value: $(printf '%q' "$v")"; run s3 2>&1 | grep -E 'error:|\[exit|firstmate:'; heads s3
done
rm -f "$S/s3/lab/config/self-update-source"; mkdir "$S/s3/lab/config/self-update-source"
echo "--- value: <a directory>"; run s3 2>&1 | grep -E 'error:|\[exit|firstmate:'; heads s3

echo; echo "=== S4: the fork branch is rewritten (non-fast-forward) -> skipped, never forced ==="
world s4; C=$(carry s4); printf 'fork carry\n' > "$S/s4/lab/config/self-update-source"
run s4 >/dev/null 2>&1; heads s4
g -C "$S/s4/seed" checkout -q -b rewritten "$C~1"; printf 'other\n' >> "$S/s4/seed/README.md"
g -C "$S/s4/seed" commit -qam rewritten; g -C "$S/s4/seed" push -q -f "$S/s4/fork.git" rewritten:carry
echo "carry=$(short s4 "$C") rewritten=$(short s4 HEAD)"
run s4; heads s4

echo; echo "=== S5: fork branch fetch fails -> primary skipped, secondmates stay on primary commit ==="
world s5; carry s5 >/dev/null; printf 'fork nosuchbranch\n' > "$S/s5/lab/config/self-update-source"
run s5; heads s5

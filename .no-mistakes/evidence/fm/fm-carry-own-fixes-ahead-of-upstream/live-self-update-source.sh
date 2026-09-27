#!/usr/bin/env bash
# Live drive of bin/fm-update.sh (the /updatefirstmate mechanical half) against a
# disposable lab FM_HOME and a real clone of the change under test.
set -u
SRC=${SRC:?}
W=$(mktemp -d "${TMPDIR:-/tmp}/fm-selfupd.XXXXXX")
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); rmdir "$LAB"
"$SRC/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/tmux"
export GIT_AUTHOR_NAME=lab GIT_AUTHOR_EMAIL=lab@example.com GIT_COMMITTER_NAME=lab GIT_COMMITTER_EMAIL=lab@example.com
unset NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE TMUX
export TMUX_TMPDIR="$LAB/tmux"
q() { git "$@" -q 2>/dev/null || git "$@"; }
# upstream = the change under test on main; fork = secondary remote
git clone -q --bare --no-local "$SRC" "$W/upstream.git"
git -C "$W/upstream.git" branch -q -f main "$(git -C "$SRC" rev-parse HEAD)"
git -C "$W/upstream.git" symbolic-ref HEAD refs/heads/main
git init -q --bare "$W/fork.git"
git clone -q "$W/upstream.git" "$W/dev"; git -C "$W/dev" checkout -q main
# primary: origin=upstream, fork=secondary remote (the recorded home layout)
git clone -q "$W/upstream.git" "$W/primary"; git -C "$W/primary" checkout -q main
git -C "$W/primary" remote add fork "$W/fork.git"
# standalone-clone secondmate registered in data/secondmates.md
git clone -q "$W/upstream.git" "$W/sm1"; git -C "$W/sm1" checkout -q main
git -C "$W/sm1" remote set-head origin main
printf 'sm1\n' > "$W/sm1/.fm-secondmate-home"
printf -- '- sm1 - lab supervisor (home: %s/sm1; scope: lab; projects: p; added 2026-09-27)\n' "$W" > "$LAB/data/secondmates.md"
run() { echo "\$ FM_HOME=\$LAB primary/bin/fm-update.sh"; FM_HOME="$LAB" "$W/primary/bin/fm-update.sh"; echo "(exit $?)"; }
short() { git -C "$1" rev-parse --short HEAD; }
base=$(short "$W/primary")
echo "== setup: primary=$base; carry = upstream main + carried fix (PR-5435-like); upstream then moves on"
git -C "$W/dev" checkout -q -b carry
echo "# carried fix" >> "$W/dev/AGENTS.md"; git -C "$W/dev" commit -qam "carried: herdr window reuse fix"
git -C "$W/dev" push -q "$W/fork.git" carry:carry
CARRY=$(git -C "$W/dev" rev-parse --short HEAD)
git -C "$W/dev" checkout -q main
echo upstream-only >> "$W/dev/README.md"; git -C "$W/dev" commit -qam "upstream-only commit"; git -C "$W/dev" push -q origin main
UP=$(git -C "$W/dev" rev-parse --short HEAD)
echo "carry=$CARRY upstream-main=$UP"
echo
echo "== S2 adversarial: malformed / unknown remote / bad branch refuse, nothing moves"
for v in "nosuchremote carry" "fork" "fork carry extra" "fork bad..branch" "-x carry"; do
  printf '%s\n' "$v" > "$LAB/config/self-update-source"
  echo "-- config/self-update-source = '$v'"; run 2>&1 | sed "s#$LAB#\$LAB#g"
  echo "primary=$(short "$W/primary") sm1=$(short "$W/sm1")"
done
echo
echo "== S1: config 'fork carry' -> primary and standalone secondmate land on carry, not upstream main"
printf 'fork carry\n' > "$LAB/config/self-update-source"
run 2>&1 | sed "s#$LAB#\$LAB#g;s#$W#\$W#g"
echo "primary=$(short "$W/primary") branch=$(git -C "$W/primary" symbolic-ref --short HEAD) sm1=$(short "$W/sm1") (expect $CARRY)"
echo "primary origin/main=$(git -C "$W/primary" rev-parse --short origin/main) (origin ref untouched by carry update; still tracks upstream)"
echo "primary remote.origin.url=$(git -C "$W/primary" remote get-url origin | sed "s#$W#\$W#")"
echo
echo "== S3: carry refreshed on demand (upstream main merged + fix) fast-forwards"
git -C "$W/dev" checkout -q carry; git -C "$W/dev" merge -q --no-edit main; git -C "$W/dev" push -q "$W/fork.git" carry:carry
CARRY2=$(git -C "$W/dev" rev-parse --short HEAD); git -C "$W/dev" checkout -q main
run 2>&1 | sed "s#$LAB#\$LAB#g;s#$W#\$W#g"
echo "primary=$(short "$W/primary") sm1=$(short "$W/sm1") (expect $CARRY2)"
echo
echo "== S4 adversarial: carry force-rewritten -> skipped, never forced"
git -C "$W/dev" checkout -q -b rewrite "$CARRY"; echo x >> "$W/dev/README.md"; git -C "$W/dev" commit -qam rewritten
git -C "$W/dev" push -q -f "$W/fork.git" rewrite:carry; git -C "$W/dev" checkout -q main
run 2>&1 | sed "s#$LAB#\$LAB#g;s#$W#\$W#g"
echo "primary=$(short "$W/primary") sm1=$(short "$W/sm1") (expect unchanged $CARRY2)"
echo
echo "== S5: file removed -> origin path used; primary ahead of origin reported diverged, not moved"
git -C "$W/dev" push -q -f "$W/fork.git" "$CARRY2:refs/heads/carry"
rm "$LAB/config/self-update-source"
echo more-upstream >> "$W/dev/README.md"; git -C "$W/dev" commit -qam "upstream moves again"; git -C "$W/dev" push -q origin main
run 2>&1 | sed "s#$LAB#\$LAB#g;s#$W#\$W#g"
echo "primary=$(short "$W/primary") (expect unchanged $CARRY2)"
echo
echo "== S6: fresh home with no file behaves exactly as origin path"
git clone -q "$W/upstream.git" "$W/primary2"; git -C "$W/primary2" checkout -q main; git -C "$W/primary2" reset -q --hard "$base"
FM_HOME="$LAB" "$W/primary2/bin/fm-update.sh" 2>&1 | sed "s#$LAB#\$LAB#g;s#$W#\$W#g"
echo "primary2=$(short "$W/primary2") (expect upstream main $(git -C "$W/dev" rev-parse --short main))"
tmux -L default kill-server 2>/dev/null || true
rm -rf "$LAB" "$W"
echo "== lab removed"

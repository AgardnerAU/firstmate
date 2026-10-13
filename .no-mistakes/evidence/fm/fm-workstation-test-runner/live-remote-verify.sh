#!/usr/bin/env bash
# Live driver: real bin/fm-remote-verify.sh against real SSH host runner@llm-box, disposable lab in TMPDIR.
set -uo pipefail
script=$1/bin/fm-remote-verify.sh
lab=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/fm-rv-live.XXXXXX")" && pwd -P)
trap 'rm -rf "$lab"' EXIT
mkdir -p "$lab/config" "$lab/repo"
git -C "$lab/repo" init -q
printf 'kept\n' > "$lab/repo/kept.txt"; printf 'gone\n' > "$lab/repo/deleted.txt"
mkdir -p "$lab/repo/tools/build"; printf 'gen\n' > "$lab/repo/tools/build/gen.sh"
printf 'MODE=test\n' > "$lab/repo/.env.test"
git -C "$lab/repo" add -A; git -C "$lab/repo" -c user.name=T -c user.email=t@e.test commit -qm one
printf 'two\n' >> "$lab/repo/kept.txt"; git -C "$lab/repo" -c user.name=T -c user.email=t@e.test commit -qam two
git -C "$lab/repo" worktree add -qb verify "$lab/tree"
t=$lab/tree
rm "$t/deleted.txt"; printf 'SECRET=x\n' > "$t/.env"; printf 'SECRET=\n' > "$t/.env.example"
mkdir -p "$t/node_modules/p"; printf 'dep\n' > "$t/node_modules/p/i.js"
printf 'ignored.key\n' > "$t/.gitignore"; printf 'PRIV\n' > "$t/ignored.key"; printf 'untracked\n' > "$t/new.txt"
head=$(git -C "$t" rev-parse HEAD)
cat > "$t/check.sh" <<'C'
set -eu
echo "remote host: $(hostname)  pwd: $PWD"
echo "HEAD=$(git rev-parse HEAD) commits=$(git rev-list --count HEAD) remotes=[$(git remote)]"
echo "git status:"; git status --porcelain
for f in kept.txt tools/build/gen.sh .env.test .env.example new.txt check.sh; do [ -e "$f" ] && echo "present: $f" || echo "MISSING: $f"; done
for f in .env ignored.key node_modules deleted.txt; do [ -e "$f" ] && echo "LEAKED: $f" || echo "absent: $f"; done
if git -c user.name=T -c user.email=t@e.test commit --allow-empty -qm x 2>/dev/null; then echo "COMMIT ALLOWED"; else echo "commit refused (read-only .git)"; fi
echo "PATH head: ${PATH%%:*}"
C
cfg="$lab/config"
run() { env -u FM_HOME FM_CONFIG_OVERRIDE="$cfg" "$script" "$@"; }
echo "== S1 unconfigured"; run "$t" true; echo "exit=$?"
echo "== S2 malformed config"; printf 'not a destination; rm -rf /\n' > "$cfg/remote-verify"; run "$t" true; echo "exit=$?"
echo "== S3 unreachable host"; printf 'runner@nonexistent.invalid\n' > "$cfg/remote-verify"; run "$t" true; echo "exit=$?"
printf 'runner@llm-box\n' > "$cfg/remote-verify"
echo "== S4 happy path (local HEAD=$head)"; run "$t" bash check.sh; echo "exit=$?"
echo "== S5 exit code pass-through"; run "$t" bash -c 'echo failing on purpose; exit 7'; echo "exit=$?"
echo "== S6 argv not evaluated + --env"; run --env CUDA_VISIBLE_DEVICES= --env FOO='a b' "$t" bash -c 'printf "argc=%s\n" $(( $# )); printf "[%s]\n" "$@"; ls pwned 2>/dev/null && echo INJECTED || echo "no injection"; echo "CUDA=[${CUDA_VISIBLE_DEVICES-unset}] FOO=[$FOO]"' _ 'a b' '$(touch pwned)'"'"'"' '*'; echo "exit=$?"
echo "== S6b invalid --env"; run --env 'BAD NAME=1' "$t" true; echo "exit=$?"
hash=$(printf %s "$t" | (command -v sha256sum >/dev/null && sha256sum || shasum -a 256) | cut -c1-16)
echo "== S7 remote cleanup of ~/.cache/firstmate/verify/$hash"
ssh -o BatchMode=yes runner@llm-box 'bash -s' <<<"ls -A \"\$HOME/.cache/firstmate/verify/$hash\" 2>&1; echo entries=\$(ls -A \"\$HOME/.cache/firstmate/verify/$hash\" 2>/dev/null | wc -l)"
echo "== local worktree untouched"; git -C "$t" status --porcelain

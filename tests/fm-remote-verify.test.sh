#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "$root/.remote-verify-test.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo" "$tmp/config" "$tmp/mock" "$tmp/remote/home/.local/bin"
git -C "$tmp/repo" init -q
printf 'committed\n' > "$tmp/repo/kept.txt"
printf 'deleted\n' > "$tmp/repo/deleted.txt"
git -C "$tmp/repo" add kept.txt deleted.txt
git -C "$tmp/repo" -c user.name=Test -c user.email=test@example.test commit -qm initial
git -C "$tmp/repo" worktree add -qb verify "$tmp/tree"
rm "$tmp/tree/deleted.txt"
printf 'SECRET=hidden\n' > "$tmp/tree/.env"

if "$root/bin/fm-remote-verify.sh" >"$tmp/out" 2>&1; then
  printf 'missing arguments succeeded\n' >&2; exit 1
fi
grep -q 'usage:' "$tmp/out"

if FM_CONFIG_OVERRIDE="$tmp/config" "$root/bin/fm-remote-verify.sh" "$tmp/tree" true >"$tmp/out" 2>&1; then
  printf 'missing config succeeded\n' >&2; exit 1
fi
grep -q 'remote verify is not configured' "$tmp/out"

printf 'runner@example.test\n' > "$tmp/config/remote-verify"
cat > "$tmp/mock/ssh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
while [ "$1" = -o ]; do shift 2; done
shift
command=$1
case "$command" in
  'printf %s "$HOME"') printf '%s' "$TEST_REMOTE_HOME";;
  *'mktemp -d'*) mkdir -p "$TEST_REMOTE_WORK"; printf '%s' "$TEST_REMOTE_WORK";;
  *) HOME=$TEST_REMOTE_HOME bash -c "$command";;
esac
MOCK
cat > "$tmp/mock/rsync" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
args=()
while [ "$#" -gt 0 ]; do
  if [ "$1" = -e ]; then shift 2; continue; fi
  case "$1" in
    runner@example.test:*) args+=("${1#runner@example.test:}");;
    *) args+=("$1");;
  esac
  shift
done
exec "$TEST_REAL_RSYNC" "${args[@]}"
MOCK
cat > "$tmp/remote/home/.local/bin/pnpm" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_PNPM_LOG"
MOCK
cat > "$tmp/tree/check.sh" <<'CHECK'
#!/usr/bin/env bash
set -euo pipefail
[ "$(git rev-parse HEAD)" = "$TEST_SOURCE_HEAD" ]
[ "$(git rev-list --count HEAD)" -eq 1 ]
[ -z "$(git remote)" ]
[ -z "$(git status --porcelain -- kept.txt)" ]
[ "$(git status --porcelain -- deleted.txt)" = ' D deleted.txt' ]
if git -c user.name=Test -c user.email=test@example.test commit --allow-empty -qm forbidden >/dev/null 2>&1; then exit 1; fi
if git config --get-regexp '^(credential\..*|remote\..*\.url|push\..*)$' >/dev/null; then exit 1; fi
if git config --get credential.helper >/dev/null; then exit 1; fi
if [ -d .git/hooks ] && [ -n "$(find .git/hooks -type f -print -quit)" ]; then exit 1; fi
[ -f kept.txt ]
[ ! -e deleted.txt ]
[ ! -e .env ]
CHECK
chmod +x "$tmp/mock/ssh" "$tmp/mock/rsync" "$tmp/remote/home/.local/bin/pnpm" "$tmp/tree/check.sh"
tree=$(cd "$tmp/tree" && pwd -P)
task_hash=$(printf %s "$tree" | shasum -a 256 | cut -c1-16)
export TEST_REMOTE_HOME="$tmp/remote/home"
export TEST_REMOTE_WORK="$TEST_REMOTE_HOME/.cache/firstmate/verify/$task_hash/work.test"
TEST_REAL_RSYNC=$(command -v rsync)
export TEST_REAL_RSYNC
export TEST_PNPM_LOG="$tmp/pnpm.log"
TEST_SOURCE_HEAD=$(git -C "$tmp/tree" rev-parse HEAD)
export TEST_SOURCE_HEAD
PATH="$tmp/mock:$PATH" FM_CONFIG_OVERRIDE="$tmp/config" "$root/bin/fm-remote-verify.sh" "$tmp/tree" bash check.sh
[ ! -e "$tmp/pnpm.log" ] || { printf 'pnpm ran without a pnpm project\n' >&2; exit 1; }

printf '{"packageManager":"pnpm@10.34.3"}\n' > "$tmp/tree/package.json"
printf 'lockfileVersion: 9.0\n' > "$tmp/tree/pnpm-lock.yaml"
PATH="$tmp/mock:$PATH" FM_CONFIG_OVERRIDE="$tmp/config" "$root/bin/fm-remote-verify.sh" "$tmp/tree" bash check.sh
grep -q '^install --frozen-lockfile --store-dir ' "$tmp/pnpm.log"

printf 'SECRET=\n' > "$tmp/tree/.env.example"
git -C "$tmp/tree" add .env.example
git -C "$tmp/tree" -c user.name=Test -c user.email=test@example.test commit -qm template
cat > "$tmp/tree/template.sh" <<'CHECK'
#!/usr/bin/env bash
set -euo pipefail
[ -f .env.example ]
[ ! -e .env ]
[ -z "$(git status --porcelain -- .env.example)" ]
CHECK
PATH="$tmp/mock:$PATH" FM_CONFIG_OVERRIDE="$tmp/config" "$root/bin/fm-remote-verify.sh" "$tmp/tree" bash template.sh

git -C "$tmp/tree" add .env
git -C "$tmp/tree" -c user.name=Test -c user.email=test@example.test commit -qm secret
if PATH="$tmp/mock:$PATH" FM_CONFIG_OVERRIDE="$tmp/config" "$root/bin/fm-remote-verify.sh" "$tmp/tree" true >"$tmp/out" 2>&1; then
  printf 'history containing a secret succeeded\n' >&2; exit 1
fi
grep -q 'Git history contains excluded secret path: .env' "$tmp/out"
printf 'fm-remote-verify: passed\n'

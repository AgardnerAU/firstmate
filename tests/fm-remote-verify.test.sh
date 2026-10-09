#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tree" "$tmp/config" "$tmp/mock"
git -C "$tmp/tree" init -q
printf '{"packageManager":"pnpm@10.34.3"}\n' > "$tmp/tree/package.json"
git -C "$tmp/tree" add package.json

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
case "$*" in
  *'printf %s "$HOME"'*) printf '/home/runner';;
  *'mktemp -d'*) printf '%s/work.test' "$TEST_REMOTE_TASK";;
  *'bash -s --'*) cat >/dev/null; exit 37;;
  *) exit 0;;
esac
MOCK
cat > "$tmp/mock/rsync" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$tmp/mock/ssh" "$tmp/mock/rsync"
set +e
tree=$(cd "$tmp/tree" && pwd -P)
task_hash=$(printf %s "$tree" | shasum -a 256 | cut -c1-16)
PATH="$tmp/mock:$PATH" FM_CONFIG_OVERRIDE="$tmp/config" TEST_REMOTE_TASK="/home/runner/.cache/firstmate/verify/$task_hash" "$root/bin/fm-remote-verify.sh" "$tmp/tree" false >"$tmp/out" 2>&1
status=$?
set -e
[ "$status" -eq 37 ] || { printf 'expected remote exit 37, got %s\n' "$status" >&2; exit 1; }
printf 'fm-remote-verify: passed\n'

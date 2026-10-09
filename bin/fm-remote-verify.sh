#!/usr/bin/env bash
# Run a local Git worktree's verification command on the configured SSH host.
# Usage: bin/fm-remote-verify.sh <worktree> <command> [argument ...]
# The command is passed as an argv vector, not evaluated as shell text.
# config/remote-verify contains exactly one user@host SSH destination.
# Git history is bundled on the Mac into a disposable remote test repository.
# Remote Git is limited to verification and throwaway test fixtures: no GitHub
# clones, worker copies, source commits, pushes, credentials, remotes, or hooks.
set -euo pipefail

usage() { printf 'usage: %s <worktree> <command> [argument ...]\n' "$0" >&2; exit 64; }
[ "$#" -ge 2 ] || usage
worktree=$1
shift
[ -d "$worktree" ] || { printf 'error: worktree is not a directory: %s\n' "$worktree" >&2; exit 64; }
worktree=$(cd "$worktree" && pwd -P)
[ "$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null)" = "$worktree" ] || {
  printf 'error: path must be a Git worktree root: %s\n' "$worktree" >&2
  exit 64
}
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
config_dir=${FM_CONFIG_OVERRIDE:-${FM_HOME:-$repo_root}/config}
config=$config_dir/remote-verify
[ -f "$config" ] || { printf 'error: remote verify is not configured; put user@host in %s\n' "$config" >&2; exit 78; }
destination=$(cat "$config")
[[ "$destination" =~ ^[a-zA-Z_][a-zA-Z_0-9-]*@[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || {
  printf 'error: %s must contain one user@host SSH destination\n' "$config" >&2
  exit 78
}
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10)
remote_home=$(ssh "${ssh_opts[@]}" "$destination" 'printf %s "$HOME"') || {
  printf 'error: remote verify host %s is unreachable; run locally if needed\n' "$destination" >&2
  exit 69
}
[[ "$remote_home" =~ ^/[a-zA-Z0-9_./-]+$ ]] || { printf 'error: unsafe remote home path\n' >&2; exit 69; }
task_hash=$(printf %s "$worktree" | shasum -a 256 | cut -c1-16)
remote_task=$remote_home/.cache/firstmate/verify/$task_hash
# Paths are validated above and intentionally expand on the client.
# shellcheck disable=SC2029
remote_work=$(ssh "${ssh_opts[@]}" "$destination" "mkdir -p '$remote_task' && mktemp -d '$remote_task/work.XXXXXXXX'") || {
  printf 'error: cannot create remote verify directory on %s\n' "$destination" >&2
  exit 69
}
[[ "$remote_work" =~ ^$remote_task/work\.[a-zA-Z0-9]+$ ]] || {
  printf 'error: unexpected remote verify directory from %s\n' "$destination" >&2
  exit 69
}
cleanup() { # shellcheck disable=SC2029
  ssh "${ssh_opts[@]}" "$destination" "chmod -R u+w '$remote_work/.git' 2>/dev/null || true; rm -rf '$remote_work' '$remote_work.template' && rm -f '$remote_work.bundle'" >/dev/null 2>&1 || true
  rm -f "$file_list" "$bundle_file"
}
file_list=$(mktemp)
bundle_file=$(mktemp)
trap cleanup EXIT

# Git selects tracked files and untracked files that are not ignored.
# rsync's exclusions apply even to tracked files; credentials stay on this Mac.
git -C "$worktree" ls-files --cached --others --exclude-standard -z | while IFS= read -r -d '' path; do
  if [ -e "$worktree/$path" ] || [ -L "$worktree/$path" ]; then
    printf '%s\0' "$path"
  fi
done > "$file_list"
git -C "$worktree" log --format= --name-only -z HEAD | while IFS= read -r -d '' path; do
  case "$path" in
    .env|.env.*|*/.env|*/.env.*|.npmrc|*/.npmrc|.pypirc|*/.pypirc|.netrc|*/.netrc|\
    .ssh/*|*/.ssh/*|.aws/*|*/.aws/*|.gnupg/*|*/.gnupg/*|\
    *.pem|*.key|*.p12|*.pfx|credentials.json|*/credentials.json|secrets.json|*/secrets.json|\
    id_rsa*|*/id_rsa*|id_ed25519*|*/id_ed25519*)
      printf 'error: Git history contains excluded secret path: %s\n' "$path" >&2
      exit 65
      ;;
  esac
done
source_head=$(git -C "$worktree" rev-parse HEAD)
git -C "$worktree" bundle create "$bundle_file" HEAD
exclude=(
  --exclude=.git --exclude=node_modules --exclude=dist --exclude=build
  --exclude=coverage --exclude=.next --exclude=.turbo --exclude=.cache
  --exclude=.env --exclude='.env.*' --exclude='.npmrc' --exclude='.pypirc'
  --exclude='.ssh' --exclude='.aws' --exclude='.gnupg' --exclude='.netrc'
  --exclude='*.pem' --exclude='*.key' --exclude='*.p12' --exclude='*.pfx'
  --exclude='credentials.json' --exclude='secrets.json'
  --exclude='id_rsa*' --exclude='id_ed25519*'
)
rsync -a --from0 --files-from="$file_list" "${exclude[@]}" -e 'ssh -o BatchMode=yes -o ConnectTimeout=10' "$worktree/" "$destination:$remote_work/"
rsync -a -e 'ssh -o BatchMode=yes -o ConnectTimeout=10' "$bundle_file" "$destination:$remote_work.bundle"

# Bash receives the command through positional parameters, avoiding remote shell evaluation.
printf -v remote_args ' %q' "$remote_work" "$source_head" "$@"
# shellcheck disable=SC2029
ssh "${ssh_opts[@]}" "$destination" "bash -s --$remote_args" <<'REMOTE'
set -euo pipefail
work=$1
source_head=$2
shift 2
trap 'chmod -R u+w "$work/.git" 2>/dev/null || true; rm -rf "$work"' EXIT
cd "$work"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_COUNT=0
mkdir "$work.template"
git init -q --template="$work.template"
rmdir "$work.template"
git bundle unbundle "$work.bundle" >/dev/null
git update-ref refs/heads/verify "$source_head"
git symbolic-ref HEAD refs/heads/verify
git read-tree HEAD
rm "$work.bundle"
chmod -R a-w .git
export GIT_OPTIONAL_LOCKS=0
export PATH="$HOME/.local/bin:$PATH"
export COREPACK_HOME="$HOME/.cache/node/corepack"
export PNPM_STORE_DIR="$HOME/.local/share/pnpm/store"
export CUDA_VISIBLE_DEVICES=''
export NVIDIA_VISIBLE_DEVICES=void
if [ -f package.json ] && [ -f pnpm-lock.yaml ]; then
  pnpm install --frozen-lockfile --store-dir "$PNPM_STORE_DIR"
fi
"$@"
REMOTE

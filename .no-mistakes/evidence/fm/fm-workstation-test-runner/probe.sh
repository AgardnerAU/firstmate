#!/usr/bin/env bash
echo "host=$(hostname) pwd=$PWD"
echo "node=$(node -v)"
echo "CUDA_VISIBLE_DEVICES=[$CUDA_VISIBLE_DEVICES] NVIDIA_VISIBLE_DEVICES=[$NVIDIA_VISIBLE_DEVICES]"
echo "head=$(git rev-parse HEAD) commits=$(git rev-list --count HEAD)"
git log --format='  log: %s'
echo "remotes=[$(git remote)]"
echo "credential.helper=[$(git config --get credential.helper)]"
echo "url/push/credential config=[$(git config --get-regexp '^(credential\..*|remote\..*|push\..*|url\..*)$')]"
echo "hook files=[$(find .git/hooks -type f 2>/dev/null)]"
echo "git status --porcelain:"; git status --porcelain | sed 's/^/  /'
echo "files:"; ls -A | grep -vx '.git' | sed 's/^/  /'
echo "commit attempt: $(git -c user.name=T -c user.email=t@e.test commit --allow-empty -qm x 2>&1 | head -1)"
echo "push attempt: $(git push 2>&1 | head -1)"
echo "throwaway fixture repo: $(d=$(mktemp -d) && git -C "$d" init -q && git -C "$d" -c user.name=T -c user.email=t@e.test commit --allow-empty -qm fx && git -C "$d" rev-list --count HEAD; rm -rf "$d")"
exit 0

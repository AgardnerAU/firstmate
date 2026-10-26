#!/usr/bin/env bash
# Extracts the "Tracked root paths must be allow-listed" step from ci.yml (via YAML parser)
# and runs it, as GitHub Actions would (bash -e), in disposable clones of the change.
set -u
WT=$1; REV=${2:-HEAD}
STEP=$(mktemp); python3 -I - "$WT/.github/workflows/ci.yml" "$STEP" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
for job in wf["jobs"].values():
    for s in job.get("steps", []):
        if s.get("name") == "Tracked root paths must be allow-listed":
            print("job:", job.get("name")); open(sys.argv[2], "w").write(s["run"]); sys.exit(0)
sys.exit("step not found")
PY
run_case() { # name, setup-cmd
  local d; d=$(mktemp -d); git clone -q "$WT" "$d/r"; git -C "$d/r" checkout -q "$REV"
  (cd "$d/r" && git config user.email t@t && git config user.name t && eval "$2" && git commit -qm case >/dev/null 2>&1 || true)
  echo "=== $1"; (cd "$d/r" && bash -e "$STEP"); echo "exit=$?"; rm -rf "$d"
}
run_case "clean tree (no extra paths)" ":"
run_case "scratch .tmp-ax/.tasks.toml (the reported leak)" "mkdir .tmp-ax && echo x > .tmp-ax/.tasks.toml && git add -f .tmp-ax"
run_case "personal fleet path state/x" "mkdir state && echo x > state/x && git add -f state"
run_case "each legacy deny-list name" "for n in data config projects .no-mistakes; do mkdir \$n; echo x > \$n/f; done; git add -f data config projects .no-mistakes"
run_case "non-ASCII scratch dir .tmp-é/x (quotePath)" "mkdir .tmp-é && echo x > .tmp-é/x && git add -f .tmp-é"
run_case "leading/trailing whitespace name ' pad /x'" "mkdir ' pad ' && echo x > ' pad /x' && git add -f ' pad '"
run_case "name with newline" "mkdir \$'nl\nx' && echo x > \$'nl\nx/f' && git add -f \$'nl\nx'"
run_case "root .tasks.toml allowed, nested allowed dir file" "echo x > .tasks.toml; echo x > docs/new-doc.md; git add -f .tasks.toml docs/new-doc.md"
run_case "prefix lookalike bin2/x and docsx file" "mkdir bin2 && echo x > bin2/x && echo x > docsx && git add -f bin2 docsx"

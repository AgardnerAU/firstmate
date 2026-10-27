set -eu
# Allow-list, not a deny-list: personal fleet paths and scratch dirs such as .tmp-ax stay out by default.
# Add a root entry here when the repository gains a new root-level file or directory.
unexpected=$(git ls-files -z | while IFS= read -r -d '' path; do
  case "${path%%/*}" in
    .agents|.claude|.codex|.cursor|.gitattributes|.github|.gitignore|.greptile|.grok|.no-mistakes.yaml|.omp|.opencode|.pi|.tasks.toml) ;;
    AGENTS.md|CLAUDE.md|CONTRIBUTING.md|GROK_BOT.md|LICENSE|README.md|VISION.md|assets|bin|docs|skills|tests) ;;
    *) printf '%s\n' "$path" ;;
  esac
done)
if [ -n "$unexpected" ]; then
  echo "::error::Tracked paths outside the root allow-list (personal fleet or scratch paths?):"
  printf '%s\n' "$unexpected"
  exit 1
fi

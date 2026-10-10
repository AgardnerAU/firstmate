#!/usr/bin/env bash
# Live drive of bin/fm-brief.sh: base (fb75c1f9) vs change, absent/blank/present writing style.
set -u
ROOT=$1; EV=$2
W=$(mktemp -d "${TMPDIR:-/tmp}/fm-ws.XXXXXX")
mkdir -p "$W/base"; git -C "$ROOT" archive fb75c1f9 | tar -x -C "$W/base"
run() { # <root> <home> <kind> <id>
  local r=$1 h=$2 k=$3 id=$4
  mkdir -p "$h/data" "$h/config"
  case $k in
    ship) env -u FM_CONFIG_OVERRIDE FM_HOME="$h" FM_ROOT_OVERRIDE="$r" "$r/bin/fm-brief.sh" "$id" some-proj --mode direct-PR ;;
    scout) env -u FM_CONFIG_OVERRIDE FM_HOME="$h" FM_ROOT_OVERRIDE="$r" "$r/bin/fm-brief.sh" "$id" some-proj --scout ;;
    secondmate) env -u FM_CONFIG_OVERRIDE FM_HOME="$h" FM_ROOT_OVERRIDE="$r" FM_SECONDMATE_CHARTER='lab charter' "$r/bin/fm-brief.sh" "$id" --secondmate --no-projects ;;
  esac >/dev/null 2>&1 || echo "  scaffold FAILED: $r $k"
}
norm() { sed -e "s#$2#__ROOT__#g" -e "s#$3#__HOME__#g" "$1"; }
for k in ship scout secondmate; do
  run "$W/base" "$W/h-base" $k t-$k
  run "$ROOT" "$W/h-absent" $k t-$k
  mkdir -p "$W/h-blank/config"; printf '\n  \n\t\n' > "$W/h-blank/config/worker-writing-style.md"
  run "$ROOT" "$W/h-blank" $k t-$k
  norm "$W/h-base/data/t-$k/brief.md" "$W/base" "$W/h-base" > "$W/base-$k"
  norm "$W/h-absent/data/t-$k/brief.md" "$ROOT" "$W/h-absent" > "$W/absent-$k"
  norm "$W/h-blank/data/t-$k/brief.md" "$ROOT" "$W/h-blank" > "$W/blank-$k"
  cmp -s "$W/base-$k" "$W/absent-$k" && echo "[$k] absent file: byte-identical to base fb75c1f9 brief" || { echo "[$k] absent DIFFERS"; diff "$W/base-$k" "$W/absent-$k"; }
  cmp -s "$W/base-$k" "$W/blank-$k" && echo "[$k] blank file:  byte-identical to base fb75c1f9 brief" || { echo "[$k] blank DIFFERS"; diff "$W/base-$k" "$W/blank-$k"; }
done
mkdir -p "$W/h-present/config"
printf '%s\n' 'Use ASD-STE100 with British spelling for human-facing prose.' 'Use plain hyphens, never typographic dashes.' > "$W/h-present/config/worker-writing-style.md"
for k in ship scout secondmate; do
  run "$ROOT" "$W/h-present" $k t-$k
  b="$W/h-present/data/t-$k/brief.md"
  echo "===== [$k] present file: first 12 lines of generated brief ====="
  head -12 "$b"
  echo "  heading count: $(grep -c '^# Worker writing style$' "$b")"
  cp "$b" "$EV/present-$k-brief.md"
done
echo "===== base->present diff (secondmate, normalised) ====="
norm "$W/h-present/data/t-secondmate/brief.md" "$ROOT" "$W/h-present" | diff "$W/base-secondmate" - 
echo "===== FM_CONFIG_OVERRIDE ====="
mkdir -p "$W/ovr" "$W/h-ovr/data" "$W/h-ovr/config"; echo 'Override-only rule.' > "$W/ovr/worker-writing-style.md"; echo 'Home rule.' > "$W/h-ovr/config/worker-writing-style.md"
FM_HOME="$W/h-ovr" FM_CONFIG_OVERRIDE="$W/ovr" "$ROOT/bin/fm-brief.sh" t-ovr some-proj --mode direct-PR >/dev/null 2>&1
grep -A1 '^# Worker writing style' "$W/h-ovr/data/t-ovr/brief.md"
echo "===== Adversarial: style text containing {TASK}, '# Task', and quotes ====="
mkdir -p "$W/h-adv/data" "$W/h-adv/config"
printf '%s\n' "Don't use \$HOME or \`backticks\` or \"quotes\" (parens)." > "$W/h-adv/config/worker-writing-style.md"
FM_HOME="$W/h-adv" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-brief.sh" t-adv some-proj --mode direct-PR >/dev/null 2>&1; echo "exit=$?"
grep -A1 '^# Worker writing style' "$W/h-adv/data/t-adv/brief.md"
rm -rf "$W"

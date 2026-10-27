#!/bin/bash
# Bounded load harness: 12 busy loops pinned to CPUs 6,7; suite pinned to the same CPUs.
E=$1; cd "$2" || exit 1
pids=()
for i in $(seq 12); do taskset -c 6,7 bash -c 'while :; do :; done' & pids+=($!); done
trap 'kill "${pids[@]}" 2>/dev/null' EXIT
sleep 60
run() { name=$1; shift; s=$SECONDS
  echo "== $name start loadavg=$(cat /proc/loadavg) nproc(pinned)=$(taskset -c 6,7 nproc)" >> "$E/load-summary.log"
  env "$@" taskset -c 6,7 timeout 1200 bash tests/fm-extension-binding.test.sh > "$E/load-$name.log" 2>&1; rc=$?
  echo "== $name rc=$rc elapsed=$((SECONDS-s))s loadavg=$(cat /proc/loadavg) last: $(tail -1 "$E/load-$name.log")" >> "$E/load-summary.log"; }
run default-1 X=1
run override-34 FM_EXTENSION_BINDING_COORDINATOR_TIMEOUT_SECONDS=34
run default-2 X=1
echo DONE >> "$E/load-summary.log"

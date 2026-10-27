#!/bin/bash
# usage: fm-load-run.sh <log> [env assignments...]
log=$1; shift
pids=()
for i in $(seq 1 12); do taskset -c 0,1 bash -c 'while :; do :; done' & pids+=($!); done
sleep 3
{
echo "hogs: ${#pids[@]} busy loops pinned to cpus 0,1 together with the suite"
echo "env: $*"
echo "uptime before: $(uptime)"
s=$(date +%s)
env "$@" taskset -c 0,1 bash tests/fm-extension-binding.test.sh
rc=$?
echo "uptime after: $(uptime)"
echo "rc=$rc elapsed=$(( $(date +%s)-s ))s"
} > "$log" 2>&1
kill "${pids[@]}"; wait 2>/dev/null

#!/usr/bin/env bash
# fm-test-env-lib.sh - single owner of the ambient fleet environment that
# Firstmate's behavior-test processes must not inherit.
#
# Firstmate launches a worker with the live home exported (bin/fm-spawn.sh sets
# FM_HOME=<home> in the launch command), so a suite started from inside a worker
# carries pointers at the real fleet home. Any test that resolves a home the
# ordinary way - bin/fm-wake-lib.sh and friends read these variables - would then
# read and write the live locks, wake queue, and task records.
#
# fm_test_env_isolate clears those pointers in the CALLING process. A runner
# calls it once, before it starts any test script, so every child inherits the
# cleared environment whichever path the run takes: serial, a --jobs worker, or
# an isolation-proof worker. Isolation therefore cannot depend on a flag, and no
# runner keeps its own copy of the list - two copies drift apart the moment one
# of them is edited.
#
# Usage (source, then call once, early):
#   . "$ROOT/bin/fm-test-env-lib.sh"
#   fm_test_env_isolate || exit 2
#
# It returns non-zero if any pointer survives, so a runner that cannot isolate
# refuses instead of running the suite against the live home.

# Every environment variable a live Firstmate session puts into a worker's
# environment and a Firstmate script then consults: the home and its durable
# records, plus the runtime control variables a session start creates. Extend
# this list, not a runner, whenever Firstmate starts exporting another one.
#
# FM_SESSION_START_STAGE_FILE is in the second class and matters as much as the
# home pointers: bin/fm-session-start.sh treats its presence as "I am already
# the bounded child" and skips its own runtime bound, so a leaked one removes
# the bound a test is asserting and the suite hangs on the fixture instead of
# failing.
FM_TEST_ENV_FLEET_POINTERS="\
FM_HOME \
FM_ROOT \
FM_ROOT_OVERRIDE \
FM_STATE_OVERRIDE \
FM_DATA_OVERRIDE \
FM_PROJECTS_OVERRIDE \
FM_CONFIG_OVERRIDE \
FM_PENDING_REPLY_DIR_OVERRIDE \
FM_PUBLIC_FOLLOWUP_PRIMARY_HOME \
FM_WAKE_QUEUE \
FM_WAKE_QUEUE_LOCK \
FM_BACKEND \
FM_SESSION_START_STAGE_FILE"

fm_test_env_isolate() {
  local name rc=0
  for name in $FM_TEST_ENV_FLEET_POINTERS; do
    unset "$name" 2>/dev/null || true
  done
  for name in $FM_TEST_ENV_FLEET_POINTERS; do
    if [ -n "${!name:-}" ]; then
      printf 'fm-test-env: could not clear %s from the environment\n' "$name" >&2
      rc=1
    fi
  done
  return "$rc"
}

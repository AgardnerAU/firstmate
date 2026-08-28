#!/usr/bin/env bash
# fm-worker-state-lib.sh - the one durable representation of an intentionally
# worker-free task.
#
# A task normally retains its endpoint metadata after fm-control exit so a
# later relaunch can reuse the same worktree and endpoint. That is not proof
# that an absent agent is intentional: an ordinary exit can be a crash. Only
# fm-control stand-down writes state/<id>.worker-state, and it writes
# `stood-down` only after the backend's recovery-grade classifier proves the
# agent is dead. The watcher skips a matching record only while that same
# classifier still sees the endpoint as dead; a live agent always remains in
# stale and wedge detection.
#
# Record format, written atomically with mode 0600:
#   schema=1
#   task_id=<exact task id>
#   endpoint=<exact current backend target>
#   state=standing-down|stood-down
#
# `standing-down` records the short transition before the exit is proved. It
# is never a suppression state, so an interrupted control action fails toward
# ordinary supervision. `stood-down` is cleared by fm-spawn --relaunch before
# it prepares the replacement. Teardown removes the record with the task's
# other endpoint-local runtime state.
#
# This is a sidecar rather than a state/<id>.meta field. Endpoint metadata is
# the relaunch identity and has independent transactional writers, so mixing a
# worker-lifecycle declaration into it would make an innocent hold capable of
# corrupting or racing that identity.

fm_worker_state_path() {  # <state-dir> <task-id>
  printf '%s/%s.worker-state' "$1" "$2"
}

# fm_worker_state_status <state-dir> <task-id> <endpoint>
# Prints one of active, standing-down, stood-down, or invalid. A record is
# valid only when every schema key appears once and the task/endpoint binding
# still matches the caller's current metadata-derived identity.
fm_worker_state_status() {
  local state_dir=$1 id=$2 endpoint=$3 record key count schema task bound state
  record=$(fm_worker_state_path "$state_dir" "$id")
  { [ -e "$record" ] || [ -L "$record" ]; } || { printf 'active'; return 0; }
  [ -f "$record" ] && [ ! -L "$record" ] || { printf 'invalid'; return 0; }
  for key in schema task_id endpoint state; do
    count=$(awk -F= -v key="$key" '$1 == key { n += 1 } END { print n + 0 }' "$record" 2>/dev/null) || {
      printf 'invalid'
      return 0
    }
    [ "$count" = 1 ] || { printf 'invalid'; return 0; }
  done
  schema=$(awk -F= '$1 == "schema" { sub(/^[^=]*=/, ""); print; exit }' "$record" 2>/dev/null) || schema=
  task=$(awk -F= '$1 == "task_id" { sub(/^[^=]*=/, ""); print; exit }' "$record" 2>/dev/null) || task=
  bound=$(awk -F= '$1 == "endpoint" { sub(/^[^=]*=/, ""); print; exit }' "$record" 2>/dev/null) || bound=
  state=$(awk -F= '$1 == "state" { sub(/^[^=]*=/, ""); print; exit }' "$record" 2>/dev/null) || state=
  [ "$schema" = 1 ] && [ "$task" = "$id" ] && [ "$bound" = "$endpoint" ] || {
    printf 'invalid'
    return 0
  }
  case "$state" in
    standing-down|stood-down) printf '%s' "$state" ;;
    *) printf 'invalid' ;;
  esac
}

# fm_worker_state_write <state-dir> <task-id> <endpoint> <state>
# The caller owns the task lifecycle lock. Refuse to replace malformed or
# symlinked state, because overwriting a record whose meaning cannot be proved
# would turn a failed control action into a false intentional stand-down.
fm_worker_state_write() {
  local state_dir=$1 id=$2 endpoint=$3 wanted=$4 record tmp prior
  case "$id" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  case "$endpoint" in ''|*$'\n'*) return 1 ;; esac
  case "$wanted" in standing-down|stood-down) ;; *) return 1 ;; esac
  record=$(fm_worker_state_path "$state_dir" "$id")
  if [ -e "$record" ] || [ -L "$record" ]; then
    [ -f "$record" ] && [ ! -L "$record" ] || return 1
    prior=$(fm_worker_state_status "$state_dir" "$id" "$endpoint")
    [ "$prior" != invalid ] || return 1
  fi
  tmp="$state_dir/.${id}.worker-state.${BASHPID:-$$}.${RANDOM}"
  if ! (
    umask 077
    {
      printf 'schema=1\n'
      printf 'task_id=%s\n' "$id"
      printf 'endpoint=%s\n' "$endpoint"
      printf 'state=%s\n' "$wanted"
    } > "$tmp"
  ); then
    rm -f -- "$tmp"
    return 1
  fi
  mv -f -- "$tmp" "$record"
}

# fm_worker_state_clear <state-dir> <task-id> <endpoint>
# A relaunch can clear only a valid state record for its own exact endpoint.
fm_worker_state_clear() {
  local state_dir=$1 id=$2 endpoint=$3 record status
  record=$(fm_worker_state_path "$state_dir" "$id")
  { [ -e "$record" ] || [ -L "$record" ]; } || return 0
  status=$(fm_worker_state_status "$state_dir" "$id" "$endpoint")
  [ "$status" != invalid ] || return 1
  rm -f -- "$record"
}

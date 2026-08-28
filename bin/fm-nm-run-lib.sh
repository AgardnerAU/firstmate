#!/usr/bin/env bash
# Shared no-mistakes axi run attribution primitives.
#
# ONE owner for the no-mistakes run-attribution primitives used by
# fm-crew-state.sh (read-only current-state reporting) and fm-teardown.sh
# (pre-teardown run abort, see its "Fix 1" header comment). Teardown uses only
# strict branch-and-head identity; crew-state additionally permits the active
# pipeline-owned exemption defined below. Getting this wrong in either
# direction is unsafe: a false negative hides a genuinely parked run, and a
# false positive lets teardown act on a run it does not own.
#
# Bounded call to `no-mistakes "$@"` in dir $1, timeout $2 seconds. The bounded
# form preserves stdout, stderr, and exit status; the checked form discards
# stderr, while fm_nm_run keeps the fail-open query contract for read-only callers.
fm_nm_run_bounded() {  # <dir> <timeout_secs> <args...>
  local dir=$1 timeout_secs=$2 have_timeout=none
  shift 2
  if command -v timeout >/dev/null 2>&1; then have_timeout=timeout
  elif command -v gtimeout >/dev/null 2>&1; then have_timeout=gtimeout
  elif command -v perl >/dev/null 2>&1; then have_timeout=perl
  fi
  case "$have_timeout" in
    timeout)  ( cd "$dir" && timeout "$timeout_secs" no-mistakes "$@" ) ;;
    gtimeout) ( cd "$dir" && gtimeout "$timeout_secs" no-mistakes "$@" ) ;;
    perl)     ( cd "$dir" && perl -e 'my $t = shift; my $pid = fork; die "fork failed" unless defined $pid; if (!$pid) { setpgrp(0, 0); exec @ARGV } local $SIG{ALRM} = sub { kill "TERM", -$pid; select undef, undef, undef, 0.2; kill "KILL", -$pid; exit 124 }; alarm $t; waitpid $pid, 0; exit($? >> 8)' "$timeout_secs" no-mistakes "$@" ) ;;
    *)        return 1 ;;
  esac
}

fm_nm_run_checked() {  # <dir> <timeout_secs> <args...>
  fm_nm_run_bounded "$@" 2>/dev/null
}

fm_nm_run() {  # <dir> <timeout_secs> <args...>
  fm_nm_run_checked "$@" || true
}

fm_nm_trim() {
  local s=${1:-}
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

fm_nm_strip_quotes() {
  local s
  s=$(fm_nm_trim "${1:-}")
  case "$s" in
    \"*\") s=${s#\"}; s=${s%\"} ;;
  esac
  fm_nm_trim "$s"
}

# Scalar value of a TOON key in captured `axi status` output $1.
fm_nm_field() {  # <toon-output> <key>
  printf '%s\n' "$1" | sed -n "s/^[[:space:]]*$2:[[:space:]]*\(.*\)/\1/p" | head -1
}

# 0 if run head $2 matches worktree $1's code identity, per the same rule
# everywhere this attribution is needed:
#   - missing/empty head: cannot bind; reject
#   - equal commits (short or full SHA): match
#   - worktree HEAD is an ancestor of run head: match (pipeline fix commits on
#     the same history advanced the run tip past local HEAD)
#   - run head is a strict ancestor of worktree HEAD, or diverged: no match
#     (local work advanced outside the run, or the branch tip was rewritten)
# fm_nm_run_is_pipeline_owned_active below carries the one exemption: a live
# run whose pipeline currently owns the branch binds without head equality.
fm_nm_head_matches_worktree() {  # <worktree> <run_head>
  local wt=$1 run_head=$2 local_full run_full
  [ -n "$run_head" ] || return 1
  local_full=$(git -C "$wt" rev-parse HEAD 2>/dev/null) || return 1
  run_full=$(git -C "$wt" rev-parse --verify "${run_head}^{commit}" 2>/dev/null) || return 1
  [ "$run_full" = "$local_full" ] && return 0
  git -C "$wt" merge-base --is-ancestor "$local_full" "$run_full" 2>/dev/null
}

# 0 if head $2 resolves to a commit object in worktree $1 at all. This
# distinguishes a PROVEN mismatch (resolvable but not current: a historical or
# diverged head fm_nm_head_matches_worktree correctly rejects) from UNKNOWN
# attribution (unresolvable: e.g. a pipeline-owned lane head that never
# reached this worktree). A caller scanning run rows newest-first must stop on
# unknown attribution rather than surface an older, superseded run.
fm_nm_head_resolvable() {  # <worktree> <head>
  [ -n "$2" ] || return 1
  git -C "$1" rev-parse --verify --quiet "$2^{commit}" >/dev/null 2>&1
}

# branch_sync.state from captured `axi status` TOON $1: the scalar directly
# under the top-level `branch_sync:` block. The first `state:` inside the
# block is the direct child (the nested local/pipeline/target/remote
# sub-blocks carry no `state:` key). Empty when the block is absent: no run
# on the current branch, another branch's run, or a CLI without branch sync.
fm_nm_branch_sync_state() {  # <toon-output>
  local s
  s=$(printf '%s\n' "$1" \
    | sed -n '/^[[:space:]]*branch_sync:[[:space:]]*$/,/^[^[:space:]][^:]*:/s/^[[:space:]]\{1,\}state:[[:space:]]*\(.*\)/\1/p' \
    | head -1)
  fm_nm_strip_quotes "$s"
}

# 0 if the run in captured `axi status` TOON $1 is still in flight: no
# terminal outcome and no terminal status.
fm_nm_run_is_active() {  # <toon-output>
  local status outcome
  status=$(fm_nm_strip_quotes "$(fm_nm_field "$1" status)")
  outcome=$(fm_nm_strip_quotes "$(fm_nm_field "$1" outcome)")
  [ -z "$outcome" ] || return 1
  case "$status" in completed|failed|cancelled) return 1 ;; esac
}

# The one exemption to the head rule above: while the pipeline OWNS the branch
# (branch_sync.state=pipeline_owned), the daemon's own branch attribution IS
# the attribution for an ACTIVE run, and
# head equality must not be required - the pipeline's lane head is routinely
# not a git object in the task worktree (rebase and fix commits that were
# never pushed back), so the head rule rejects exactly the run that is most
# current. The exemption never applies to a terminal run: a terminal run has
# released the branch, and binding one by branch name alone is the historical
# reused-branch misattribution the head rule exists to prevent.
fm_nm_run_is_pipeline_owned_active() {  # <toon-output>
  [ "$(fm_nm_branch_sync_state "$1")" = pipeline_owned ] || return 1
  fm_nm_run_is_active "$1"
}

# Record why a run question could not be answered, for the caller's refusal
# message. FM_NM_RUN_UNKNOWN_REASON is this file's second return value on rc 2.
fm_nm_run_unknown() {  # <reason>
  # shellcheck disable=SC2034 # read by callers through the documented contract.
  FM_NM_RUN_UNKNOWN_REASON=$1
}

# The bounded window every runs-listing scan reads. `no-mistakes runs` takes
# only --limit: no pagination, no "that was all" marker, so a full window is
# indistinguishable from a truncated one and can never prove a negative. The
# default is the historical 200; an operator whose fleet fills that window can
# widen it here for BOTH readers, which is why the safety caller no longer
# takes a private hardcoded cap.
fm_nm_runs_limit() {
  local n=${FM_NM_RUNS_LIMIT:-200}
  case "$n" in ''|*[!0-9]*|0) n=200 ;; esac
  printf '%s' "$n"
}

# Coarse run attribution from the top-level `no-mistakes runs` listing, the
# one fallback for the routine case where bare `axi status` answers with
# ANOTHER branch's run (several crews validating the same underlying repo share
# one no-mistakes registration) or does not answer at all. The listing is plain
# text, newest-first, "<status> <branch> <short-sha> <date> [<pr-url>]"
# separated by runs of spaces (no quoting), so branch plus the same head
# identity rule used above is an exact read of "is there a run for THIS branch".
#
# The scan reads the WHOLE listing for this branch, because the status column is
# each run's CURRENT status: an older row that still says `running` is a live
# run, not history, however many finished rows sit above it. Stopping at the
# first row would answer "nothing is in flight" while that run holds the branch.
#
# It answers on several separate channels, because reporting and safety need
# different things from the same rows:
#   FM_NM_RUNS_STATUS            the status word to RENDER: the first row whose
#                                head places against this worktree, and nothing
#                                once an unresolvable head has been seen, so a
#                                superseded older row is never rendered as the
#                                current state.
#   FM_NM_RUNS_ACTIVE_ATTRIBUTED "<status> <sha>" of a non-terminal row that
#                                places here: a live run this task owns.
#   FM_NM_RUNS_TRUNCATED         1 when the listing came back exactly full, so
#                                the window may have cut off older rows. The
#                                interface offers no pagination and no
#                                end-of-list marker, so a full window is not an
#                                exhausted one: it can still answer that a run
#                                IS live, but it can never prove that none is.
#                                FM_NM_RUNS_LIMIT_USED carries the window size
#                                the answer was read through.
#   FM_NM_RUNS_UNATTRIBUTED_ACTIVE  "<status> <sha>" of a non-terminal row that
#                                does NOT place here (mismatched or
#                                unresolvable head): a live run on this branch
#                                that cannot be tied to this worktree's code
#                                identity. The head rule exists to reject a
#                                HISTORICAL run on a reused branch, and a
#                                non-terminal row is not history, so this is
#                                doubt - never proof of safety.
# The return code carries only the reporting answer: 0 when FM_NM_RUNS_STATUS
# was set, 2 when the CLI itself could not answer, 1 otherwise. A caller whose
# safety depends on the result reads the two liveness channels, not the word.
fm_nm_runs_scan_for_branch() {  # <worktree> <branch> <timeout_secs> [limit]
  local wt=$1 branch=$2 timeout=$3 limit=${4:-} out rc row st rest br sha
  local render_locked=0 rows=0
  case "$limit" in ''|*[!0-9]*|0) limit=$(fm_nm_runs_limit) ;; esac
  FM_NM_RUNS_STATUS=
  FM_NM_RUNS_ACTIVE_ATTRIBUTED=
  FM_NM_RUNS_UNATTRIBUTED_ACTIVE=
  FM_NM_RUNS_TRUNCATED=
  FM_NM_RUNS_LIMIT_USED=$limit
  [ -n "$branch" ] || return 1
  if out=$(fm_nm_run_checked "$wt" "$timeout" runs --limit "$limit"); then rc=0; else rc=$?; fi
  [ "$rc" = 0 ] || return 2
  while IFS= read -r row; do
    row=$(fm_nm_trim "$row")
    [ -n "$row" ] || continue
    rows=$((rows + 1))
    st=${row%% *}
    rest=$(fm_nm_trim "${row#* }")
    br=${rest%% *}
    rest=$(fm_nm_trim "${rest#* }")
    sha=${rest%% *}
    [ "$br" = "$branch" ] || continue
    if fm_nm_head_matches_worktree "$wt" "$sha"; then
      if [ "$render_locked" = 0 ] && [ -z "$FM_NM_RUNS_STATUS" ]; then
        FM_NM_RUNS_STATUS=$st
      fi
      case "$st" in
        completed|failed|cancelled) ;;
        *)
          [ -n "$FM_NM_RUNS_ACTIVE_ATTRIBUTED" ] \
            || FM_NM_RUNS_ACTIVE_ATTRIBUTED="$st $sha"
          ;;
      esac
      continue
    fi
    case "$st" in
      completed|failed|cancelled) ;;
      *)
        [ -n "$FM_NM_RUNS_UNATTRIBUTED_ACTIVE" ] \
          || FM_NM_RUNS_UNATTRIBUTED_ACTIVE="$st $sha"
        ;;
    esac
    fm_nm_head_resolvable "$wt" "$sha" || render_locked=1
  done <<< "$out"
  [ "$rows" -lt "$limit" ] || FM_NM_RUNS_TRUNCATED=1
  [ -z "$FM_NM_RUNS_STATUS" ] || return 0
  return 1
}

# The printing form, for a reader that only wants the status word and treats
# every unanswered question as silence. The scan above is the form a caller
# whose safety depends on the answer must use: a command substitution runs in a
# subshell, so its FM_NM_RUNS_* answers cannot reach the caller through this one.
fm_nm_runs_status_for_branch() {  # <worktree> <branch> <timeout_secs> [limit]
  local rc=0
  fm_nm_runs_scan_for_branch "$@" || rc=$?
  printf '%s' "$FM_NM_RUNS_STATUS"
  return "$rc"
}

# Whether worktree $1, on branch $2, currently owns an IN-FLIGHT no-mistakes
# run, under the same attribution both readers use (exact branch match plus head
# identity, with the pipeline-owned exemption) and, when bare `axi status`
# cannot settle it, the coarse runs-list fallback above. ONE attribution for
# every caller: a stand-down that consulted fewer sources than current-state
# reporting would remove a gated run from supervision that fm-crew-state can
# still see.
#
# Three-valued, because "no run is active" and "nobody could tell me" are
# different answers and only the first is safe to act on:
#   0 - an active run is attributed to this task; FM_NM_ACTIVE_RUN_ID names it
#       when the answering source carried an id (the coarse listing has none).
#   1 - proved: no active run is attributed to this task.
#   2 - could not answer; FM_NM_RUN_UNKNOWN_REASON names the check that failed.
# A caller for whom a live run is a refusal condition must refuse on 2 as well
# as 0. An absent CLI is a proven 1, not an unanswered question: with no
# no-mistakes installed there is no run to own the branch. Answer 1 needs BOTH
# sources to agree: one live run from either is enough to answer 0, but only a
# successful whole-branch listing that found nothing live AND came back short of
# its window - a full window may have cut the live row off - can prove the
# negative.
#
# THE GOVERNING RULE AT EVERY DECISION BELOW: IF IT CANNOT BE PROVEN SAFE, IT
# IS REFUSED, AND THE REFUSAL NAMES WHAT COULD NOT BE PROVEN. So a non-terminal
# run row for this branch that the head rule could not place is answer 2 with
# the attribution named, never answer 1 - an unplaceable live run is exactly
# the doubt this contract exists to carry, and only rc 1 licenses acting.
fm_nm_active_run_for_worktree() {  # <worktree> <branch> <timeout_secs>
  local wt=$1 branch=$2 timeout=$3 out rc run_branch run_head coarse_rc
  local unattributed=
  # shellcheck disable=SC2034 # the attributed run id is this function's second
  # return value, read by the caller that refuses on it.
  FM_NM_ACTIVE_RUN_ID=
  fm_nm_run_unknown ""
  [ -d "$wt" ] || {
    fm_nm_run_unknown "worktree '$wt' is not readable, so no run check could run"
    return 2
  }
  # No branch (detached HEAD) means there is no branch a run could own here.
  [ -n "$branch" ] || return 1
  command -v no-mistakes >/dev/null 2>&1 || return 1
  if out=$(fm_nm_run_checked "$wt" "$timeout" axi status); then rc=0; else rc=$?; fi
  if [ "$rc" = 0 ] && [ -n "$out" ]; then
    run_branch=$(fm_nm_strip_quotes "$(fm_nm_field "$out" branch)")
    if [ -n "$run_branch" ] && [ "$run_branch" = "$branch" ]; then
      run_head=$(fm_nm_strip_quotes "$(fm_nm_field "$out" head)")
      if fm_nm_head_matches_worktree "$wt" "$run_head" \
        || fm_nm_run_is_pipeline_owned_active "$out"; then
        if fm_nm_run_is_active "$out"; then
          # shellcheck disable=SC2034 # read by callers through the documented contract.
          FM_NM_ACTIVE_RUN_ID=$(fm_nm_strip_quotes "$(fm_nm_field "$out" id)")
          return 0
        fi
      elif fm_nm_run_is_active "$out"; then
        unattributed="the run 'no-mistakes axi status' reports on branch $branch (head ${run_head:-unknown}) cannot be placed against this worktree's HEAD"
      fi
    fi
  fi
  # Only a LIVE run is settled by bare `axi status`, and every other outcome
  # falls through to here: it answered about another branch, its same-branch
  # attribution failed, it named a finished run, or it did not answer at all.
  # A finished answer is not proof either, for the same reason a finished
  # listing row is not - `axi status` reports the most recent run, and an
  # earlier run on this branch can still be in flight behind it - so no hold is
  # licensed until the whole-branch listing has answered too. Its silence is
  # not an answer.
  if fm_nm_runs_scan_for_branch "$wt" "$branch" "$timeout" "$(fm_nm_runs_limit)"; then
    coarse_rc=0
  else
    coarse_rc=$?
  fi
  if [ -n "$FM_NM_RUNS_ACTIVE_ATTRIBUTED" ]; then
    return 0
  fi
  if [ -n "$FM_NM_RUNS_UNATTRIBUTED_ACTIVE" ] && [ -z "$unattributed" ]; then
    unattributed="the 'no-mistakes runs' listing shows a non-terminal run for branch $branch (${FM_NM_RUNS_UNATTRIBUTED_ACTIVE}) that cannot be placed against this worktree's HEAD"
  fi
  # A named live run outranks the generic "the CLI said nothing" reason: the
  # refusal has to name what could not be proven, not send the operator back to
  # a listing that already answered.
  if [ -n "$unattributed" ]; then
    fm_nm_run_unknown "$unattributed"
    return 2
  fi
  if [ "$coarse_rc" = 2 ]; then
    fm_nm_run_unknown "'no-mistakes runs --limit' could not answer whether branch $branch has an active run"
    return 2
  fi
  if [ "${FM_NM_RUNS_TRUNCATED:-}" = 1 ]; then
    fm_nm_run_unknown "'no-mistakes runs --limit ${FM_NM_RUNS_LIMIT_USED}' came back exactly full, so it cannot prove branch $branch has no run still in flight - an older live run may sit past that window (widen it with FM_NM_RUNS_LIMIT)"
    return 2
  fi
  return 1
}

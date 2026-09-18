# Live fleet-home isolation - test transcript (branch fm/fm-test-suites-not-isolated-from-live-home)

All commands run from the worktree. $SENTINEL is a throwaway directory standing in for the LIVE fleet home;
FM_HOME and the other fleet pointers were exported at it, the way firstmate exports them into a worker.

## 1. Reproduction at base 9bc051f (before the change): suites inherit the live home
$ env FM_HOME=$SENTINEL ... bash tests/<suite>.test.sh   # base checkout via git archive
  fm-gotmp             exit 1   not ok - teardown exited non-zero with a valid tasktmp
  fm-gitignore-config  exit 1   fatal: not a git repository ... not ok - git does not ignore config/...
  fm-afk-launch        exit 0   WROTE INTO THE SENTINEL LIVE HOME: $SENTINEL/state
  fm-backend-tmux-smoke exit 0  sentinel untouched

## 2. Same four suites at HEAD c852396: pass and leave the live home untouched
  fm-gotmp  exit 0  sentinel entries: []   last line: ok - fm-teardown skips gracefully when tasktmp= points to a nonexistent dir
  fm-afk-launch  exit 0  sentinel entries: []   last line: ok - tmux e2e: record + .afk cleared on stop
  fm-backend-tmux-smoke  exit 0  sentinel entries: []   last line: ok - real tmux: kill removes the window and the readable session inventory authoritatively classifies it missing
  fm-gitignore-config  exit 0  sentinel entries: []   last line: ok - scratchpad2/ does not make git status --porcelain dirty

## 3. Runner path (bin/fm-test-run.sh) with the same polluted environment
$ env FM_HOME=$SENTINEL FM_TRACE_CONTEXT=leaked FM_SUPERVISION_MODEL=autoarm bash bin/fm-test-run.sh tests/fm-gotmp.test.sh tests/fm-afk-launch.test.sh
  FM_TEST_SUMMARY total=2 failed=0 skipped_gate=0 duration_ms=45034   (exit 0, sentinel entries: [])

## 4. Concurrent proof harness (bin/fm-test-isolation-proof.sh --pool snapshot-bearings --jobs 2), same polluted environment
  FM_ISOLATION_SUMMARY total=5 failed=0 concurrency=2 duration_ms=224516   (exit 0, sentinel entries: [])

## 5. Repo-wide invariant (tests/fm-test-env-lib.test.sh) on the real tests/ directory
  ok - all 217 behavior suites reach the fleet-environment isolation owner
  (plus the owner, refusal, non-vacuity and route cases - all ok, exit 0)

## 6. Adversarial: a new suite cannot skip isolation silently
  a) dropped tests/zz-unisolated-decoy.test.sh (never isolates) into the real tests/ dir:
     invariant exit 1 - not ok - these suites never isolate their top-level shell through bin/fm-test-env-lib.sh, so they can be handed the live fleet home:     zz-unisolated-decoy.test.sh 
  b) dropped tests/zz-preisolation-write-decoy.test.sh (writes a fake task record through the
     inherited FM_HOME, THEN isolates):
     invariant exit 1 - not ok - these suites never isolate their top-level shell through bin/fm-test-env-lib.sh, so they can be handed the live fleet home:     zz-preisolation-write-decoy.test.sh 
  Both decoys were removed afterwards; git status is clean.

## 7. Adversarial: an unclearable pointer refuses instead of running
$ bash -c 'readonly FM_HOME=$SENTINEL; . tests/fm-trace-context-lib.test.sh'   -> exit 2
  fm-test-env: could not clear FM_HOME from the environment
  tests/lib.sh: refusing to run a suite against the live fleet home
$ bash -c 'readonly FM_HOME=$SENTINEL; . bin/fm-test-run.sh --list --family orca'   -> exit 2
  fm-test-env: could not clear FM_HOME from the environment
  fm-test-run: refusing to run: the live fleet home is still reachable
  Sentinel untouched in both cases.

## 8. Selection: a change to the isolation owner selects the suites it can break
$ touch a comment onto bin/fm-test-env-lib.sh; bash bin/fm-test-run.sh --list --changed --base HEAD
  217 scripts selected, including the five that reach the owner only through an intermediate helper:
    tests/fm-grok-harness.test.sh
    tests/fm-codex-hook-layer-live-e2e.test.sh
    tests/fm-claude-trust.test.sh
    tests/fm-spawn-worktree-settle.test.sh
    tests/fm-watch-recovery-loop.test.sh
  (working tree restored afterwards; git status clean)

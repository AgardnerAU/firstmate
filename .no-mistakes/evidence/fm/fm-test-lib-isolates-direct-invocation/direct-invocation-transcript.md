# Direct suite invocation from inside a firstmate worker

Every run below is `bash tests/<suite>.test.sh` executed with a live home's
pointers exported (see `worker-environment.txt`) - the exact end-user path this
change fixes. "before" = `tests/lib.sh` at the base commit (no isolation),
"after" = the branch as delivered. Nothing else differs between the two columns.

## 1. The reported case: tests/fm-pending-reply.test.sh

before, en_AU.UTF-8:
    ok - wrong-home reports are detected but do not silently acknowledge
    not ok - unmarked crewmate send should succeed: expected exit 0, got 1
    exit 1

before, LC_ALL=C:
    not ok - unmarked crewmate send should succeed: expected exit 0, got 1
    exit 1                      <- same failure, so it is not locale sensitivity

after, en_AU.UTF-8 and LC_ALL=C:
    ok - all pending-reply tests passed
    exit 0

## 2. The assertion still protects the behaviour (disconfirming experiment)

With the fix in place, the `kind=secondmate` condition at bin/fm-send.sh:476 was
removed so crewmate steers get marked too:

    not ok - crewmate steer should be recorded unmarked
    exit 1

So the case is still red when the behaviour it guards is taken away - it was not
made green by weakening it. bin/fm-send.sh was restored unchanged afterwards.

## 3. The four sibling fm-send suites, same environment

    suite                                before   after
    tests/fm-send-inbox.test.sh             1        0    "an inbox-plane steer should exit 0 at enqueue: expected exit 0, got 1"
    tests/fm-send-resolve-key.test.sh       1        0    "an answer send with --resolve-key should succeed: expected exit 0, got 1"
    tests/fm-send-strict.test.sh            1        0    "exact task id send should succeed when metadata exists: expected exit 0, got 1"
    tests/fm-send-secondmate-marker.test.sh 1        0    "send to a secondmate target should succeed: expected exit 0, got 1"

## 4. tests/fm-session-start.test.sh (the accepted "same missing isolation" item)

    before: exit 1 after 7s - "not ok - digest did not print projects.md content"
    after:  exit 0 after 245s - "# fm-session-start.test.sh: all assertions passed"

(The synthetic sentinel home here makes the pre-fix run fail fast rather than run
past its bound; either way the suite is red without the fix and green with it.)

## 5. The live home was never touched

The sentinel home was byte-identical before and after every "after" run:

    <LIVE_HOME>/state/.wake-queue  ->  "sentinel"
    no new entries created anywhere under <LIVE_HOME>

## 6. A pointer that cannot be cleared refuses hard, and does not latch

    $ FM_STATE_OVERRIDE readonly in the sourcing shell, then `. tests/lib.sh`
    before: FM_TEST_LIB_SOURCED=unset
    fm-test-env: could not clear FM_STATE_OVERRIDE from the environment
    tests/lib.sh: refusing to run a suite against the live fleet home
    exit=2                      <- the suite body is never reached

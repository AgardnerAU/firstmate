# `--changed` over-selects for a pointer-list edit

A single-file edit to `bin/fm-test-env-lib.sh` (nothing else changed in the tree),
listed through the runner's own selection:

    $ bash bin/fm-test-run.sh --changed --base HEAD --list | grep -c test.sh

    without the mapping fix:   32 suites   (pure-contract-unit only)
    with the mapping fix:     162 suites   (the same broad scan tests/lib.sh gets)

Because `tests/lib.sh` now sources that library, its pointer list shapes the
environment of every suite, so a pointer edit must select the suites it can break.
The runner's own header states the map must over-select rather than under-select.

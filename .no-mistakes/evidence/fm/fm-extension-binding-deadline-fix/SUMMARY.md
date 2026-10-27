# Extension-binding coordinator deadline - live validation (commit f21df91f)

Load simulation: 12 bash busy loops pinned with the suite to CPUs 0,1 (fm-load-run.sh).
The suite gets about 0.13 of a core. On this 8-core host, a host load of 45 gives about 0.18 of a core, so this simulation is heavier, similar to a host load of about 60.

| Run | Coordinator deadline | Result | Elapsed |
|---|---|---|---|
| normal-load-run.log | 120 (default) | pass | 19 s |
| loaded-run-fixed-1.log | 120 (default) | pass | 140 s |
| loaded-run-old-34s-deadline.log | 34 (old value through env) | FAIL: "an isolated extension conformance section failed" | 90 s |
| loaded-run-fixed-2.log | 120 (default) | FAIL: same message. The lifecycle-flow lane stopped after crash-silent with no "not ok", so the coordinator deadline killed it | 204 s |
| loaded-lifecycle-flow-alone.log | n/a (section alone) | pass, but it takes 134 s, more than the 120 s cap | 134 s |
| guard-121.log | 121 | rejected (coordinator returns 64) | 9 s |
| guard-120.log | 120 | pass | 25 s |

# bin/fm-watch.sh under a lock creation the environment refuses

Driven as an operator arms the watcher: `FM_STATE_OVERRIDE=<scratch> bin/fm-watch.sh`,
with an on-PATH `mktemp` that refuses every `<lock>.owner.XXXXXX` creation
(the "no space / no permission / no fork" shape) and records how deep into the
reclaim-marker chain each refused path sat.

## Base (bin/fm-wake-lib.sh from 9bc051f, the pre-fix library)

```
VERDICT=hung-after-60s        # killed by the harness, still growing
stdout: (nothing - no watcher ever armed, no message to the operator)
reclaim-marker creation attempts: 169
deepest marker depth reached:     168
stderr:                           897736 bytes, 391 x "File name too long"
```

First error line (truncated):

```
basename: /var/folders/41/64hrmnwx11q5lw3l9d7zmfgr0000gn/T/tmp.pfRfor0u6h/state/.watch.lock.steal.steal.steal.steal.steal.steal.steal.steal.steal.steal.steal.steal.steal.steal.stea...
```

This is the recorded 2026-08-24 incident shape: armed, entered the loop, died in
it, megabytes of "File name too long", nothing supervised.

## Target (952f298, this branch merged with current main)

```
VERDICT=exited rc=0 after 1s
stdout: watcher: already running
reclaim-marker creation attempts: 2   # the first attempt plus the single bounded retry
deepest marker depth reached:     0   # no reclaim mutex opened for a lock that does not exist
stderr:                           0 bytes
```

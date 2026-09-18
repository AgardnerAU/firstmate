# bin/fm-watch.sh against seeded reclaim-marker chains (target commit, no shims)

## Adversarial: chain seeded deeper than the published bound (7 levels, all dead holders)

```
$ FM_STATE_OVERRIDE=<scratch> bin/fm-watch.sh
watcher: already running pid 99999
exit 0, after ~1s
deepest .steal path on disk afterwards: 6   # unchanged - the chain was not grown
stderr: 0 bytes, 0 x "File name too long"
```

Past the bound the watcher reports a definite outcome and stops instead of
naming another marker.

## Non-regression: ordinary crash leftover (1 marker level, dead holder)

```
$ FM_STATE_OVERRIDE=<scratch> bin/fm-watch.sh
armed=1  lock pid now 98570 (was the seeded dead pid 99999)
marker levels left on disk: 0
stderr: 0 bytes
```

The dead holder is still reclaimed and the watcher arms, so ordinary
self-healing is unchanged.

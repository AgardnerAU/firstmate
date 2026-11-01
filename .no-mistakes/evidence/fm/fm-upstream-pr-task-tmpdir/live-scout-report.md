# tdir-live report

## What I did
Ran in the worker shell (worktree /tmp/fml.IBGh/th/.treehouse/demo-cb26de/1/demo):

```
echo "TMPDIR=[$TMPDIR]"; echo "TMP=[$TMP]"; echo "TEMP=[$TEMP]"
```

## Findings (output)
```
TMPDIR=[/tmp/fm-tdir-live/tmp]
TMP=[/tmp/fm-tdir-live/tmp]
TEMP=[/tmp/fm-tdir-live/tmp]
```

All three variables are set and agree: `/tmp/fm-tdir-live/tmp` (a per-task temp directory).

## Recommendation
None. No work to ship. No captain decisions open (empty inventory).

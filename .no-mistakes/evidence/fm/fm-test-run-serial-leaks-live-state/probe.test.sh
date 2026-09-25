#!/usr/bin/env bash
# transient probe: report every fleet pointer this test inherited
names="FM_HOME FM_ROOT FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE FM_CONFIG_OVERRIDE FM_PENDING_REPLY_DIR_OVERRIDE FM_PUBLIC_FOLLOWUP_PRIMARY_HOME FM_WAKE_QUEUE FM_WAKE_QUEUE_LOCK FM_BACKEND FM_SESSION_START_STAGE_FILE FM_SUPERVISION_MODEL FM_TRACE_CONTEXT"
leak=0
for n in $names; do if [ -n "${!n+x}" ]; then echo "LEAKED $n=${!n}"; leak=1; fi; done
if [ -n "${FM_HOME:-}" ]; then touch "$FM_HOME/state/probe-wrote-here"; fi
if [ "$leak" = 0 ]; then echo "probe $(basename "$0"): no fleet pointer inherited"; fi
exit $leak

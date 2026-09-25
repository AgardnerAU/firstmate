#!/usr/bin/env bash
# Throwaway repo copy whose proven set also names the two probes, so --jobs 2 admits them.
W="$PWD"; S="$W/.probe-sentinel-home"; R=$(mktemp -d "${TMPDIR:-/tmp}/fm-jobs-probe.XXXXXX")
mkdir -p "$R/bin" "$R/tests"
cp "$W/bin/fm-test-env-lib.sh" "$R/bin/"
sed 's#^tests/fm-arm-pretool-check.test.sh$#tests/fm-arm-pretool-check.test.sh\ntests/zz-probe-a.test.sh\ntests/zz-probe-b.test.sh#' "$W/bin/fm-test-run.sh" >"$R/bin/fm-test-run.sh"
chmod +x "$R/bin/fm-test-run.sh"; cp "$W"/tests/zz-probe-*.test.sh "$R/tests/"; cp "$W/tests/git-config-helpers.sh" "$R/tests/" 2>/dev/null
rm -f "$S/state/probe-wrote-here"
LEAK=(FM_HOME=$S FM_ROOT=$S FM_ROOT_OVERRIDE=$S FM_STATE_OVERRIDE=$S/state FM_DATA_OVERRIDE=$S/data FM_PROJECTS_OVERRIDE=$S/p FM_CONFIG_OVERRIDE=$S/config FM_PENDING_REPLY_DIR_OVERRIDE=$S/pr FM_PUBLIC_FOLLOWUP_PRIMARY_HOME=$S FM_WAKE_QUEUE=$S/state/wq FM_WAKE_QUEUE_LOCK=$S/state/wq.lock FM_BACKEND=tmux FM_SESSION_START_STAGE_FILE=$S/stage FM_SUPERVISION_MODEL=autoarm FM_TRACE_CONTEXT=on)
echo "== concurrent: fm-test-run.sh --jobs 2 (probes admitted as proven) with all 15 worker pointers exported =="
(cd "$R" && env "${LEAK[@]}" bin/fm-test-run.sh --jobs 2 tests/zz-probe-a.test.sh tests/zz-probe-b.test.sh); echo "exit=$?"
echo "sentinel home state/ after --jobs run: [$(ls -A "$S/state")]"
echo; echo "== real proven-isolated suites via --jobs 2 with leaked pointers =="
env "${LEAK[@]}" bin/fm-test-run.sh --jobs 2 tests/fm-brief.test.sh tests/fm-cd-pretool-check.test.sh 2>&1 | grep -E '^FM_TEST_(END|SUMMARY )'; echo "exit=${PIPESTATUS[0]}"
echo "sentinel home tree after real suites: [$(cd "$S" && find . -mindepth 1 | tr '\n' ' ')]"
rm -r "$R"

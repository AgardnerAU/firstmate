#!/usr/bin/env bash
# Drive the real bin/fm-watch.sh against a disposable FM_HOME whose PR poll
# registration records a different st_dev than the live volume (a remount).
set -u
ROOT=$1 MODE=$2
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
H=$LAB/home; S=$H/state; mkdir -p "$S" "$H/data" "$H/config" "$LAB/wt" "$LAB/fakebin"
git -C "$LAB/wt" init -q && git -C "$LAB/wt" -c user.name=t -c user.email=t@e commit -q --allow-empty -m init
cat > "$LAB/fakebin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_GH_LOG"
case " $* " in *" state "*|*"--json state"*) printf 'MERGED\n' ;; esac
SH
chmod +x "$LAB/fakebin/gh"
. "$ROOT/bin/fm-pr-lib.sh"
url=https://github.com/o/r/pull/1
printf 'window=fm-task-a\nworktree=%s\npr=%s\n' "$LAB/wt" "$url" > "$S/task-a.meta"; chmod 600 "$S/task-a.meta"
fm_pr_url_parse "$url"
fm_pr_poll_prepare "$S" task-a "$FM_PR_PROVIDER" "$url" "$FM_PR_HOST" "$FM_PR_PATH" "$FM_PR_NUMBER" "$ROOT/bin/fm-pr-poll.sh" && fm_pr_poll_publish_prepared || { echo "arm failed"; exit 1; }
dev=$(fm_pr_file_device "$S")
echo "live state device: $dev"
echo "registration lines 10-11 before: $(sed -n 10,11p "$S/task-a.pr-poll-registration" | tr '\n' ' ')"
awk -v d="$dev" -v n="$((dev+1))" 'NR==10||NR==11 { sub("^" d ":", n ":") } {print}' "$S/task-a.pr-poll-registration" > "$S/.r" && chmod 600 "$S/.r" && mv -f "$S/.r" "$S/task-a.pr-poll-registration"
echo "registration lines 10-11 after renumber: $(sed -n 10,11p "$S/task-a.pr-poll-registration" | tr '\n' ' ')"
if [ "$MODE" = tamper ]; then printf '# tampered\n' >> "$S/task-a.check.sh"; echo "tampered: appended a line to task-a.check.sh"; fi
if [ "$MODE" != tamper ]; then printf '#!/usr/bin/env bash\nprintf "stop-cycle\\n"\n' > "$S/z-stop.check.sh"; chmod 700 "$S/z-stop.check.sh"
FM_HOME="$H" "$ROOT/bin/fm-check-register.sh" z-stop >/dev/null; fi
echo "--- bin/fm-watch.sh output ---"
FM_GH_LOG=$LAB/gh.log FM_HOME="$H" FM_CHECK_INTERVAL=0 FM_POLL=0.02 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 \
  PATH="$LAB/fakebin:/usr/bin:/bin" timeout 60 "$ROOT/bin/fm-watch.sh"
echo "watch exit=$?"
echo "--- gh calls ---"; cat "$LAB/gh.log" 2>/dev/null || echo "(no gh call)"
echo "--- poll artifacts left ---"; ls "$S" | grep '^task-a\.' 

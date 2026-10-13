#!/usr/bin/env bash
# Extract the base commit's bin/ into a temp root and run the same live driver against it.
set -u
WT=$1 DRIVER=$2 REV=$3
B=$(mktemp -d "${TMPDIR:-/tmp}/fm-base.XXXXXX")
trap 'rm -rf "$B"' EXIT
git -C "$WT" archive "$REV" bin | tar -x -C "$B"
bash "$DRIVER" "$B" 2>&1 | sed -n '1,9p'

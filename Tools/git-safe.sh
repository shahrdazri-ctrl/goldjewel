#!/usr/bin/env bash
# git with retries for the USB-backed lab volume.
# Usage: Tools/git-safe.sh <git arguments...>
set -uo pipefail

attempts=5
for attempt in $(seq 1 "$attempts"); do
  out=$(git "$@" 2>&1)
  status=$?
  if [ "$status" -eq 0 ]; then
    printf '%s\n' "$out"
    exit 0
  fi
  if printf '%s' "$out" | grep -qiE 'input/output error|error reading|unable to read|cannot read|bad file descriptor|index file corrupt'; then
    printf 'git %s failed (attempt %s/%s) on a volume error; retrying in 5s\n' "$1" "$attempt" "$attempts" >&2
    sleep 5
    continue
  fi
  printf '%s\n' "$out" >&2
  exit "$status"
done

printf 'git %s failed after %s attempts\n' "$1" "$attempts" >&2
exit 1

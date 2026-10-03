#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD/build/live-activity-qa"
mkdir -p "$root"
for attempt in 1 2; do
  status=0
  ACTIVITY_QA_DIR="$root/attempt-$attempt" bash Tests/LiveActivity/check.sh || status=$?
  printf 'Attempt %s: exit %s\n' "$attempt" "$status" | tee -a "$root/attempts.txt"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '\nLive Activity %s, attempt %s: exit %s. Full results and system logs retained.\n' \
      "${ACTIVITY_APPEARANCE:-dark}" "$attempt" "$status" >> "$GITHUB_STEP_SUMMARY"
  fi
  if [ "$status" -eq 0 ]; then exit 0; fi
  if [ "$status" -ne 2 ] || [ "$attempt" -eq 2 ]; then exit "$status"; fi
  echo "::warning::Live Activity first attempt failed. Repeating the complete suite once on fresh simulators; assertions are unchanged."
done

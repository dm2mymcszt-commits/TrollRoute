#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD/build/live-activity-qa"
mkdir -p "$root"
retry_methods=""
for attempt in 1 2; do
  status=0
  ACTIVITY_TEST_METHODS="$retry_methods" ACTIVITY_QA_DIR="$root/attempt-$attempt" bash Tests/LiveActivity/check.sh || status=$?
  printf 'Attempt %s: exit %s\n' "$attempt" "$status" | tee -a "$root/attempts.txt"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '\nLive Activity %s, attempt %s: exit %s. Full results and system logs retained.\n' \
      "${ACTIVITY_APPEARANCE:-dark}" "$attempt" "$status" >> "$GITHUB_STEP_SUMMARY"
  fi
  if [ "$status" -eq 0 ]; then exit 0; fi
  if [ "$status" -ne 2 ] || [ "$attempt" -eq 2 ]; then exit "$status"; fi
  if [ ! -s "$root/attempt-$attempt/failed-methods.txt" ]; then
    echo "UI failure did not identify its failed scenarios; refusing an incomplete retry."
    exit 1
  fi
  retry_methods=$(cat "$root/attempt-$attempt/failed-methods.txt")
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '\nFirst-attempt failed scenarios (each will run once more on a fresh simulator):\n%s\n' \
      "$retry_methods" >> "$GITHUB_STEP_SUMMARY"
  fi
  echo "::warning::Live Activity first attempt failed. Retrying only the recorded failed scenarios once on fresh simulators; all outcome assertions are unchanged."
done

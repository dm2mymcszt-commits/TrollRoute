#!/bin/bash
# Sourced by the runner and its policy tests. Keep compatible with macOS Bash 3.2.
all_methods=(testDynamicIslandControls testMinimalAndLockScreen testNotificationCentreControls
  testSpecificPlaceOpensPickerAndAppliesFavorite testSpeedSeekReturnAndToggleDoNotStopRoute)
methods=("${all_methods[@]}")
if [ -n "${ACTIVITY_TEST_METHODS:-}" ]; then
  methods=()
  seen_methods='|'
  while IFS= read -r method; do
    allowed=false
    for original in "${all_methods[@]}"; do
      if [ "$method" = "$original" ]; then allowed=true; break; fi
    done
    if [ "$allowed" != true ]; then echo "Invalid retry scenario: $method"; exit 1; fi
    # Under nounset, Bash 3.2 cannot expand an empty array even after methods=().
    # Validate duplicates before appending the first item.
    case "$seen_methods" in
      *"|$method|"*) echo "Duplicate retry scenario: $method"; exit 1 ;;
    esac
    seen_methods="$seen_methods$method|"
    methods+=("$method")
  done <<< "$ACTIVITY_TEST_METHODS"
fi

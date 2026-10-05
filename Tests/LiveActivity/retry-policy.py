"""Exercise the actual retry wrapper with deterministic process outcomes."""
from pathlib import Path
import os
import json
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASH = os.environ.get("QA_BASH") or ("C:/Program Files/Git/bin/bash.exe" if os.name == "nt" else "/bin/bash")
ORIGINALS = re.findall(r"func (test\w+)\(", (ROOT / "Tests/LiveActivity/SystemTests.swift").read_text())
CHECK = r'''#!/bin/bash
set -euo pipefail
source Tests/LiveActivity/methods.sh
mkdir -p "$ACTIVITY_QA_DIR"
printf '%s\n' "${methods[@]}" > "$ACTIVITY_QA_DIR/selected-methods.txt"
printf 'call\n' >> calls.txt
if [ "$(wc -l < calls.txt | tr -d ' ')" = 1 ]; then
  case "$QA_POLICY_CASE" in
    success) exit 0 ;;
    setup) exit 1 ;;
    missing) exit 2 ;;
    recovered|failed)
      if [ -n "${ACTIVITY_TEST_METHODS:-}" ]; then
        printf '%s\n' "${methods[@]}" > "$ACTIVITY_QA_DIR/failed-methods.txt"
      else
        printf '%s\n' testNotificationCentreControls testSpecificPlaceOpensPickerAndAppliesFavorite > "$ACTIVITY_QA_DIR/failed-methods.txt"
      fi
      exit 2 ;;
  esac
fi
expected=$(cat "$(dirname "$ACTIVITY_QA_DIR")/attempt-1/failed-methods.txt")
test "$ACTIVITY_TEST_METHODS" = "$expected" || exit 99
if [ "$QA_POLICY_CASE" = recovered ]; then exit 0; fi
exit 2
'''

(ROOT / "build").mkdir(exist_ok=True)
for selection in ["", "testDynamicIslandControls"]:
    for scenario, expected_code, expected_calls in [
        ("success", 0, 1), ("recovered", 0, 2), ("failed", 2, 2), ("setup", 1, 1), ("missing", 1, 1)
    ]:
        with tempfile.TemporaryDirectory(prefix="retry-policy-", dir=ROOT / "build") as directory:
            fixture = Path(directory).resolve()
            assert fixture.is_relative_to((ROOT / "build").resolve())
            scripts = fixture / "Tests/LiveActivity"
            scripts.mkdir(parents=True)
            shutil.copyfile(ROOT / "Tests/LiveActivity/run.sh", scripts / "run.sh")
            shutil.copyfile(ROOT / "Tests/LiveActivity/methods.sh", scripts / "methods.sh")
            (scripts / "check.sh").write_text(CHECK, encoding="utf-8", newline="\n")
            result = subprocess.run([BASH, "Tests/LiveActivity/run.sh"], cwd=fixture,
                env={**os.environ, "QA_POLICY_CASE": scenario, "ACTIVITY_TEST_METHODS": selection,
                     "GITHUB_STEP_SUMMARY": ""}, capture_output=True, text=True)
            assert result.returncode == expected_code, (scenario, result.returncode, result.stdout, result.stderr)
            assert (fixture / "calls.txt").read_text().splitlines() == ["call"] * expected_calls
            ledger = (fixture / "build/live-activity-qa/attempts.txt").read_text()
            assert "Attempt 1:" in ledger and ("Attempt 2:" in ledger) == (expected_calls == 2)
            selected = (fixture / "build/live-activity-qa/attempt-1/selected-methods.txt").read_text().splitlines()
            if selection:
                assert selected == [selection]
            else:
                assert len(selected) == 5 and sorted(selected) == sorted(ORIGINALS)
            if expected_calls == 2:
                retry = (fixture / "build/live-activity-qa/attempt-2/selected-methods.txt").read_text().splitlines()
                assert retry == ([selection] if selection else
                    ["testNotificationCentreControls", "testSpecificPlaceOpensPickerAndAppliesFavorite"])

# Exercise the real selector, including the first append to an empty array on
# the stock macOS /bin/bash used by CI. No simulator or replaced selector here.
for selection, expected_code, expected in [
    ("testDynamicIslandControls", 0, ["testDynamicIslandControls"]),
    ("testMinimalAndLockScreen\ntestDynamicIslandControls", 0,
     ["testMinimalAndLockScreen", "testDynamicIslandControls"]),
    ("testMissing", 1, None),
    ("testMinimalAndLockScreen\ntestMinimalAndLockScreen", 1, None),
]:
    result = subprocess.run([BASH, "-c",
        'set -euo pipefail; source Tests/LiveActivity/methods.sh; printf "%s\\n" "${methods[@]}"'], cwd=ROOT,
        env={**os.environ, "ACTIVITY_TEST_METHODS": selection}, capture_output=True, text=True)
    assert result.returncode == expected_code, (selection, result.stdout, result.stderr)
    if expected is not None:
        assert result.stdout.splitlines() == expected
# The workflow must cover every original test in both appearances even though
# each job now owns a single scenario and its bounded retry.
workflow = (ROOT / ".github/workflows/trollstore.yml").read_text()
matrix = json.loads(re.search(r"scenario: (\[[^\n]+\])", workflow).group(1))
assert len(matrix) == len(set(matrix)) == 5 and sorted(matrix) == sorted(ORIGINALS)
assert "appearance: [dark, light]" in workflow
assert "ACTIVITY_TEST_METHODS: ${{ matrix.scenario }}" in workflow
print("PASS: all five scenarios in both appearances, full/local and single/CI selection, only failed scenarios retry once, no setup or unidentified retries")

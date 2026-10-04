"""Exercise the actual retry wrapper with deterministic process outcomes."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASH = os.environ.get("QA_BASH") or ("C:/Program Files/Git/bin/bash.exe" if os.name == "nt" else "/bin/bash")
CHECK = r'''#!/bin/bash
set -euo pipefail
mkdir -p "$ACTIVITY_QA_DIR"
printf 'call\n' >> calls.txt
if [ "${ACTIVITY_TEST_METHODS:-}" = "" ]; then
  case "$QA_POLICY_CASE" in
    success) exit 0 ;;
    setup) exit 1 ;;
    missing) exit 2 ;;
    recovered|failed)
      printf '%s\n' testNotificationCentreControls testSpecificPlaceOpensPickerAndAppliesFavorite > "$ACTIVITY_QA_DIR/failed-methods.txt"
      exit 2 ;;
  esac
fi
expected=$(printf '%s\n' testNotificationCentreControls testSpecificPlaceOpensPickerAndAppliesFavorite)
test "$ACTIVITY_TEST_METHODS" = "$expected" || exit 99
if [ "$QA_POLICY_CASE" = recovered ]; then exit 0; fi
exit 2
'''

(ROOT / "build").mkdir(exist_ok=True)
for scenario, expected_code, expected_calls in [
    ("success", 0, 1), ("recovered", 0, 2), ("failed", 2, 2), ("setup", 1, 1), ("missing", 1, 1)
]:
    with tempfile.TemporaryDirectory(prefix="retry-policy-", dir=ROOT / "build") as directory:
        fixture = Path(directory).resolve()
        assert fixture.is_relative_to((ROOT / "build").resolve())
        scripts = fixture / "Tests/LiveActivity"
        scripts.mkdir(parents=True)
        shutil.copyfile(ROOT / "Tests/LiveActivity/run.sh", scripts / "run.sh")
        (scripts / "check.sh").write_text(CHECK, encoding="utf-8", newline="\n")
        result = subprocess.run([BASH, "Tests/LiveActivity/run.sh"], cwd=fixture,
            env={**os.environ, "QA_POLICY_CASE": scenario, "GITHUB_STEP_SUMMARY": ""}, capture_output=True, text=True)
        assert result.returncode == expected_code, (scenario, result.returncode, result.stdout, result.stderr)
        assert (fixture / "calls.txt").read_text().splitlines() == ["call"] * expected_calls
        ledger = (fixture / "build/live-activity-qa/attempts.txt").read_text()
        assert "Attempt 1:" in ledger and ("Attempt 2:" in ledger) == (expected_calls == 2)
print("PASS: original suite first, only failed scenarios retry once, retained failures, no setup or unidentified retries")

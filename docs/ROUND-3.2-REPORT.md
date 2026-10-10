# TrollRoute 3.2.0 (57)

## What changed

A headless keeper runs from the signed main executable while a simulated location is active. It uses persona root spawning, a kernel singleton lock, bounded privileged control helpers and Jetsam protection. Main-app entitlements are updated; extensions keep their existing entitlements and use the main executable as a control relay. The keeper exits when the session stops or its installed executable disappears. A changed build/path replaces the previous keeper.

The keeper watches locationd exit events and checks its identity every 30 seconds as a safety net. Following an exit, it discovers/retries at 0, 0.15, 0.5, 1, 2, 4 and 8 seconds. Every attempt constructs a new CLSimulationManager and sends stop, clear, append, flush, start. The complete last sample is read under the shared authority lock, including timestamp, altitude, course, speed and both motion accuracies. Continuous app/share injections also detect service replacement and recreate their connection. The idle safety check does not reinject.

Stop first terminates the keeper independently, then revokes shared authority and clears the snapshot before stopping simulation, and verifies termination again afterward. Privileged start/stop controllers serialize independently of the keeper. TERM has a bounded wait and escalates to KILL after checking process identity and executable. Errors are visible. Holding at route arrival remains active. Shared files written by root are owned by mobile and tested for actual writing after dropping root privileges.

Settings shows keeper state, start time, restart count and last restart, and lets the owner view/share a bounded event log. The log contains typed events, millisecond times, process IDs, attempts and numeric errors, never coordinates or addresses. Restart notifications are enabled by default, subject to notification permission. The map distinguishes requested position from observed delivery. Foreground monitoring learns a positive software-simulation marker; otherwise it compares recent expected positions and explicitly labels the result unverified. A discrepancy triggers one restoration request per loss episode, with a persistent notice. Keeper-start failures do not stop an otherwise running route.

A saved session from a different/unknown boot is inactive until the owner explicitly sets it again. Opening the app does not restore a position after a phone reboot. Legacy snapshots without boot identity also require confirmation; this deliberately avoids silently reactivating an old position after an update.

## Deliberate diagnostic

Settings > Diagnostics presents an exposure warning and requires a separate confirmation. A fresh one-shot request asks the live keeper to send TERM to the verified locationd executable once. It never runs at launch or on a timer. No deliberate device restart was performed during implementation.

The foreground app records every location received for 15 seconds, including receipt and sample timestamps, the raw simulation marker and whether it matches the request, without coordinates. The result includes keeper exit/replacement observations and each restore attempt. App-side automatic recovery is suppressed during this diagnostic so the result measures the keeper. Leaving the foreground or stopping interrupts the measurement.

A reported interval is between observed deliveries, not a guaranteed upper bound on exposure. No observed real update does not establish zero leakage in other apps, cached locations or gaps between callbacks. If source markers are unavailable or never verified, the result is inconclusive even when coordinates match. Private API calls provide no acknowledgement that simulation was accepted.

## Validation

Passed locally on Windows:

- App identity, group/container and version checks.
- Settings persistence/defaults regression.
- App text contains no emoji.
- Existing Live Activity retry-policy tests (all scenarios).
- Git whitespace/diff checks.

Added executable macOS tests under `Tests/Keeper/check.sh` for lifecycle activation/idempotency, service exit/replacement, exact sample preservation, stopped-session rejection, concurrent Stop/restore ordering, durable revocation after a driver failure, passive reboot loading, bounded log schema/timestamps, and diagnostic interval reporting. A separate root-to-mobile test verifies real file access after atomic writes. Injection tests now require a full restart after service identity changes. Existing motion tests remain intact. Running/stopped keeper Settings previews are included in the screenshot workflow; existing preview hosts include the new UI models without privileged execution.

**Xcode compilation, signed-package inspection, Swift tests and simulator UI checks are pending CI.** This Windows workspace has no Xcode. The owner authorized export after a privacy check; commits use the private GitHub email. CI is running. Package upload is prioritized before longer tests, and UI jobs wait for the build to free macOS capacity. No CI success or device-level success is claimed. The existing workflow includes the keeper tests and retains all previous checks.

## Deviations and remaining device checks

- Stable kernel boot UUID replaces a time-derived boot identity, so wall-clock adjustments do not look like reboots. If unavailable, automatic recovery is refused.
- Bounded post-exit discovery is necessary because exit notification can precede the replacement process. It is separate from the 30-second idle check.
- The app's positive source marker is learned from actual foreground deliveries; positional fallback remains visibly unverified. It is not claimed to identify every real update.
- Notification delivery from a headless root process, private API readiness, root process watching across iOS 15/16/17, app-update replacement and survival after swipe-away require physical-device verification.
- Root is currently used for the whole keeper. Minimum possible privileges have not been established.
- Jetsam protection does not prove immunity from all process termination. Multi-day energy use has not been measured.
- If the replacement service appears after the bounded recovery window, discovery falls back to the 30-second check. Exposure in that case can be longer.
- The cause of locationd restarting remains outside this round. The keeper restores state after a restart; it does not prevent the restart or guarantee zero real-position exposure.

## Device checklist

Use the CI package only after its build and checks pass.

1. Set a simulated location, swipe TrollRoute away, reopen it and verify Settings shows the keeper running and shared state still works.
2. Leave it for a day with normal use. Verify the keeper is still running and inspect battery use and the log.
3. Set the simulated position at the real place. Run Diagnostics and save the result, including whether the simulation marker was verified.
4. If ready to accept the stated exposure risk, repeat with a different position and check Maps on another device or after the test. Check for a position jump. The local result alone cannot prove what other clients received.
5. Press Stop. Verify the real position returns and stays, and the keeper is gone. Repeat using applicable route and Live Activity stop controls.
6. Start a driving route and run Diagnostics during it. Verify movement continues and Snapchat still displays the driving Bitmoji. Inspect course/speed preservation through the existing tests and observed behavior.
7. Reboot. Verify simulation is gone. Opening TrollRoute must offer explicit reactivation and must neither claim an active spoof nor move location automatically.
8. Update an installed build while the keeper is active; verify replacement rather than duplicate processes. Verify removal ends the keeper. Check unavailable permissions/protection errors are clear.

No release was published. Raw investigation material remains private and is not part of these commits.

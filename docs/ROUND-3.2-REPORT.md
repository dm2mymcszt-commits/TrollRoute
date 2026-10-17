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

All checks for the initial implementation at `f016d23` passed in [CI run 38040514368](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/38040514368), including Xcode compilation, signed-package inspection, keeper tests and the existing simulator UI suites. The actual application also passed the separate [iOS 15 startup check](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/38040792194). The package was delivered. Device feedback shows a running keeper and delivery marked as simulated; a deliberate service-restart measurement has not yet been supplied.

The subsequent UI follow-up replaces the bottom rectangle with a compact, rounded status button opening Settings. Initial and transient unavailable-location states show waiting rather than a spurious stopped warning or error 0. Check keeper presents an explicit result; Start is visibly disabled when already running. A manual start bypasses the short automatic-start cache so a recently terminated keeper can actually be started. Full notices remain in Safety settings. Dark/light status captures were reviewed; the capsule clears MapKit attribution and the home indicator.

All 16 jobs passed for `acc53b1` in [CI run 38158211355](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/38158211355). This includes compilation, signed-package inspection, keeper lifecycle/recovery/ownership, injection and motion preservation, route models, sharing and the full simulator UI suite. All 12 map/Settings interaction tests passed with zero failures, including fresh double-tap zoom, repeated Check feedback, Start availability and transient location errors. Final repository cleanup changes documentation only relative to this validated commit.

Earlier validation encountered a job timeout after successful map tests and screenshot uploads, an Xcode IDE disconnection on a rerun, and a five-second zoom-observation timeout with an empty accessibility hierarchy while the preview remained visible. The zoom test now allows 15 seconds to observe the same result, sends the gesture only once, and checks foreground state; its zoom and no-selection assertions remain intact. The map job budget is 25 minutes for the expanded previews and cleanup. The successful final map job took 18 minutes 22 seconds. These adjustments change only tests/CI, not application behavior.

Delivered package from the successful run: `TrollRoute-3.2.0-57-acc53b1.tipa`. SHA256: `7b46688d283497e114e60d9f15788f8b8b35d1b3917e3eb886258cca2f4144a4`. Local package inspection confirmed app/extension entitlements and deployment targets. Application source is unchanged from the previously delivered `3aab9fb` package; reinstalling solely for the test/CI changes is unnecessary.

Items 1-6 remain in their original commits; the UI follow-up is one additional commit. The temporary round plan and progress files were updated through completion, archived locally outside version control, and removed from the final commit as required. No physical-device diagnostic measurement has been supplied, so that part of the checklist remains for the owner.

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

## 3.2.1 incident hotfix (build 58)

A subsequent real-device incident invalidated the assumption that successful Jetsam configuration calls established memory protection. Read-only kernel diagnostics showed the keeper terminated in the idle band under memory pressure, before a later memory-limit termination of the location service. Opening the app restored simulation; an already-dead keeper could neither recover the service nor send a notification. Raw logs, exact incident times, identifiers, locations and screenshots remain private.

The native helper requested critical priority 19 unconditionally. Apple XNU changed critical priority to 190 on Darwin 22/23 (iOS 16/17), while Darwin 21 (iOS 15) uses 19. On the newer kernel, 19 lies in a reserved aging range and is normalized to idle priority 0 while the setter returns success. The priority revision macro is unchanged and cannot distinguish these ABIs. References: [XNU 8019 constants](https://github.com/apple-oss-distributions/xnu/blob/xnu-8019.41.5/bsd/sys/kern_memorystatus.h), [XNU 8792 constants](https://github.com/apple-oss-distributions/xnu/blob/xnu-8792.41.9/bsd/sys/kern_memorystatus.h), and [XNU 10002 normalization and priority readback](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/kern/kern_memorystatus.c).

The fix chooses the constant from the running Darwin major version, applies priority after the other configuration calls, and queries the kernel's effective priority for the keeper PID. Unexpected entry size/PID, failed queries, silent coercion and unsupported kernels are errors, never success. The existing 30-second timer verifies effective priority and repairs demotion without periodic location injection. It writes a monotonic verification timestamp; foreground status rejects unverified, failed, stale, wrong-boot or wrong-build records. Verification failure while the keeper remains alive preserves service watching and attempts a notification when enabled. Sudden termination still cannot be reported by that terminated process.

The bounded log includes measured priority on startup and protection error/recovery transitions, without coordinates. Existing logs without that field remain readable. Build 58 replaces an old keeper through the existing update path; the owner must open the updated application. The patch version intentionally advances beyond the completed round's 3.2.0 requirement so the installed fix and helper replacement are distinguishable. Original round commits remain intact.

Executable C regressions compile the same protection implementation used by the native helper, with an injected kernel interface. They reproduce successful coercion of 19 to 0, verify all three supported Darwin versions, demotion repair, configuration sequencing, setter/query failures, malformed replies and unsupported kernels. The previous Swift keeper tests did not execute this native configuration path; they could not detect this defect. Additional Swift tests cover legacy log decoding and stale/failed protection records. Existing Stop and motion behavior is unchanged.

Local validation passed: native C regressions with Clang and warnings as errors, identity/version, Settings persistence, app text and whitespace checks. Xcode compilation, signed-package verification and the keeper, motion, session and injection regressions passed in [CI run 39033060645](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/39033060645). All 16 workflow jobs passed across attempts 1 and 2. The initial light speed Live Activity runner was killed before test execution; the single failed job passed on a fresh runner with unchanged source and assertions. Map/Settings, route-session, sharing and all Live Activity scenarios passed. The owner installed build 58 and supplied a fresh startup entry with error=0 and priority=190, confirming effective-priority readback on the device. Subsequent read-only USB process checks confirmed replacement of the old keeper and continuity of the same new keeper for about 30 minutes, while the location service remained unchanged. Long-term survival and restoration delay still require owner verification. The correction addresses the confirmed idle-priority defect; it does not establish immunity from all termination or zero location exposure.

Delivered hotfix: `TrollRoute-3.2.1-58-7bd8193.tipa`, SHA256 `9991ce52894d40c023a70f7632e86891d1d91632344b3c26ae8067847ba22371`. Local inspection also verified the archive identity, deployment targets and entitlements of all executable components.

Item 8 is complete in one additional hotfix commit. Final report consolidation and removal of the temporary trackers change documentation only relative to validated application source `7bd8193`; the installed package remains the validated package. Tracking files are archived privately under build/. Original round commits are preserved.

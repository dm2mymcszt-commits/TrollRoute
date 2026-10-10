# Round 3.2 progress

## Item 1 ? implemented
UI-free relay/root modes, kernel singleton lock, app-update replacement, uninstall check, persona and Jetsam calls, main-app entitlements, same-boot launch, and mobile-owned atomic files implemented. Added fake-spawner and actual root-to-mobile file tests. Windows has no Xcode; these Swift/Apple checks await CI. Signing equality check reads the updated entitlements unchanged.

## Decisions
- A process watcher reacts to exit; bounded startup/recovery attempts are distinct from the 30-second idle safety check.
- A persisted boot identity prevents an old snapshot from automatically restoring after reboot.
- Main-app executable is also the privileged control helper. Extensions can launch its unprivileged relay without acquiring the main app's extra entitlements.

## Item 2 ? implemented
Keeper watches the service with a process-exit dispatch source. Discovery/recovery retries at 0, 0.15, 0.5, 1, 2, 4 and 8 seconds; idle PID safety check is 30 seconds and never injects while unchanged. Every attempt creates a new manager and reads the full sample under the authority lock. The app/share adapter checks service incarnation before each injection. Added fake watcher/scheduler, inactive session, metadata and restart regressions.

## Item 3 ? implemented
All existing Stop paths converge on LocationSession.stop. It terminates independently before acquiring authority (including a stuck keeper), revokes and clears the snapshot before the external Stop, and terminates/verifies again afterward to close concurrent-start races. Root start/stop controllers serialize with a separate kernel lock; identity and executable are checked before signaling, TERM escalates to KILL, failures surface as an app error. Authority waits are bounded. Holding at arrival does not invoke Stop. Added durable revocation failure/race regression.

## Item 4 ? implemented
Typed, bounded event journal (512 entries / 128 KiB), numeric errors and millisecond timestamps without coordinates. Settings exposes lifecycle/restart details, view/share log, retry/Stop and notification preference. Foreground delivery observation verifies positive simulation markers and otherwise compares recent expected positions, labels fallback as unverified, and requests recovery once per loss episode. Reboot/unknown legacy snapshots are inactive until explicit reactivation. Requested map annotation is labeled honestly. Added log tests and running/stopped Settings previews. Notification delivery from the headless process and source markers require device verification.

## Item 5 ? implemented
Separate Diagnostics action with explicit exposure warning and confirmation. A privileged relay sends a fresh one-shot request to the live keeper; only the keeper handles SIGUSR1 and signals the verified locationd executable once. The foreground observer records every delivered update for 15 seconds (including sample timestamps and raw source flags, no coordinates). Reports include the keeper timeline, observed intervals, interrupted/unknown cases and limits. App-side automatic restoration is disabled only during this test to measure the keeper itself. No device test has been triggered by development.

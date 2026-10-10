# Round 3.2 progress

## Item 1 ? implemented
UI-free relay/root modes, kernel singleton lock, app-update replacement, uninstall check, persona and Jetsam calls, main-app entitlements, same-boot launch, and mobile-owned atomic files implemented. Added fake-spawner and actual root-to-mobile file tests. Windows has no Xcode; these Swift/Apple checks await CI. Signing equality check reads the updated entitlements unchanged.

## Decisions
- A process watcher reacts to exit; bounded startup/recovery attempts are distinct from the 30-second idle safety check.
- A persisted boot identity prevents an old snapshot from automatically restoring after reboot.
- Main-app executable is also the privileged control helper. Extensions can launch its unprivileged relay without acquiring the main app's extra entitlements.

## Item 2 ? implemented
Keeper watches the service with a process-exit dispatch source. Discovery/recovery retries at 0, 0.15, 0.5, 1, 2, 4 and 8 seconds; idle PID safety check is 30 seconds and never injects while unchanged. Every attempt creates a new manager and reads the full sample under the authority lock. The app/share adapter checks service incarnation before each injection. Added fake watcher/scheduler, inactive session, metadata and restart regressions.

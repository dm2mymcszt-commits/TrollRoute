# Round 3.2 plan

1. Keeper process, entitlements, singleton, lifecycle and shared-file ownership.
2. Event-driven locationd recovery and restart-aware injection.
3. Serialized Stop, independent privileged termination and verification.
4. Bounded private-free event log, honest UI, reboot handling and notifications.
5. Explicit foreground diagnostic restart and measured delivery report.
6. Tests, CI, version 3.2.0 (57), report and removal of tracking files.

One commit per item. Never commit the private investigation or build/. No README edits or release. Device diagnostics are owner-triggered only. Use the existing shared authority lock for every restore and stop. No periodic injection.

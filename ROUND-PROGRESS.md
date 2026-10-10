# Round 3.2 progress

- Items 1-6: complete at f016d23. All checks passed in run 38040514368; actual app launch on iOS 15 passed in run 38040792194. Package delivered.
- Device feedback: keeper shown running and simulated delivery reported. No deliberate restart measurement supplied yet.
- Item 7 committed as 292df7d: compact map status, initial checking state, transient location-error handling, explicit Check result and inactive Start control while already running. Manual Start bypasses the short lifecycle cache to really check/start when needed.
- Local identity, no-emoji, Settings-default and whitespace checks passed. Added UI regression for repeated Check results and Start availability; added map status previews.
- CI run 38073322385: compilation, package signatures, keeper lifecycle/recovery/ownership, location-session and injection tests passed. Remaining build/UI checks are running.
- Delivered updated package `build/TrollRoute-3.2.0-57-292df7d.tipa` (SHA256 f77a9750a41582e243e513e9bdb21798a02d68b5525932baabb5ee6d051ed77c). Local identity and signature inspection passed.
- All 12 map/Settings interaction tests passed, including repeated Check feedback and transient-error handling. Reviewed dark/light map and Settings captures; raised the compact status by 24 points to leave MapKit attribution clear. This final spacing adjustment needs a rebuilt package and refreshed preview.
- Next: finish CI and deliver the package with the final spacing, then record validation in the report. Private investigation and build files remain excluded.

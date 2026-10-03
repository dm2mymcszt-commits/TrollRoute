# TrollRoute verification

## Released baseline

**3.0.0, build 54**, released as [v3.0.0](https://github.com/dm2mymcszt-commits/TrollRoute/releases/tag/v3.0.0) on 2026-10-03 from `fd7d417`. `d7f68df` subsequently updates only the separately maintained README and images.

[Build 54 CI](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37047452599) is green on attempt 3. All seven jobs ultimately passed; package/model checks passed on the first attempt. Live Activity first-attempt failures were 4/5 tests in dark and 3/5 in light. Final success does not establish repeatability. [Build 54 package artifact](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37047452599/artifacts/11246230243).

Earlier evidence remains in Git history: [build 53](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/36228389628) for light/dark Live Activity and iOS 17 intent metadata; [build 52](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/36126233477) for import lockout; [iOS 15 launch](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/35969628430). Do not infer exact iOS 17.0 hardware behavior from newer simulator runtimes.

## 3.1 work in progress

| Item | Status and evidence |
| --- | --- |
| Phase 0 | Plan/audit committed as `e477baa`. [Documentation CI](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37113319872) reproduced a light Live Activity failure; dark, sharing, route-session and icons passed, build/map still running at last check. Green-CI acceptance not met. Existing source findings rechecked. |
| Plane | Design only. OurAirports public-domain subset measured at 4,134 scheduled-service land airports, approximately 690 KB. No new runtime source or entitlement yet. |
| Train | Pending owner source decision. No public endpoint yet verified for permitted app use, coverage and reliability; no substitute implemented. |
| History and Settings | Not implemented. Simulator screenshots and owner layout approval still required. |
| F7/F8 | Prepared locally: existing TrollRoute icon reused in share extension; system symbols replace emoji; unused translated emoji string removed. Identity and emoji checks pass locally; iOS build/package verification pending. |
| F9 | Separate injection-adapter change prepared locally. Time-zone notification bounded to once/minute after 5 km, or after five minutes and 250 m. No injection cadence/start/stop change. Actual-adapter tests added; execution in Actions and device clock/driving Bitmoji checks pending. |
| F10 | This documentation update records build 54 and the new device checklist. |
| F11 | Investigation only. First failed dark artifact contains 25 nil-archive renderer errors, and a failed companion teardown precedes later presentation failures. Root-cause fix and several unchanged-code runs remain required. No assertions removed. |
| Delivery | No 3.1 package/version bump yet. Full regression and device checks outstanding. No 3.1 Release created. |

## Verification gate

Use the existing full workflow for package identity/signatures/entitlements, migration, motion metadata, session ownership/injection, route models/engine/finish actions, altitude budgets, access/map safety, worldwide search, sharing, map/picker previews, and UI/system controls. Add each phase's required model/fixture/UI tests. Preserve every unrelated assertion. A green package job alone is not a green workflow.

The [device checklist](BUILD-TROLLSTORE.md) covers private injection, clock changes, Snapchat, background/locked operation, sharing and new-mode playback. All are pending for the eventual 3.1 candidate. Settings/History approval is also outstanding. README.md and docs/readme are maintained separately and have not been edited.

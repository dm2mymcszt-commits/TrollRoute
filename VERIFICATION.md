# TrollRoute verification

## Released baseline

**3.0.0, build 54**, released as [v3.0.0](https://github.com/dm2mymcszt-commits/TrollRoute/releases/tag/v3.0.0) on 2026-10-03 from `fd7d417`. `d7f68df` subsequently updates only the separately maintained README and images.

[Build 54 CI](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37047452599) is green on attempt 3. All seven jobs ultimately passed; package/model checks passed on the first attempt. Live Activity first-attempt failures were 4/5 tests in dark and 3/5 in light. Final success does not establish repeatability. [Build 54 package artifact](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37047452599/artifacts/11246230243).

Earlier evidence remains in Git history: [build 53](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/36228389628) for light/dark Live Activity and iOS 17 intent metadata; [build 52](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/36126233477) for import lockout; [iOS 15 launch](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/35969628430). Do not infer exact iOS 17.0 hardware behavior from newer simulator runtimes.

## 3.1 work in progress

| Item | Status and evidence |
| --- | --- |
| Phase 0 | Source/code audit recorded in `ROUND-AUDIT.md`. BRouter refused permission; [offline France audit](docs/OFFLINE-RAIL-AUDIT.md) passed. Owner cancelled Train after reviewing it; rail acceptance is withdrawn. |
| Plane | Great-circle/profile/elevation, full engine, all finish/Stop actions and airport/preview/playback UI passed. Both Activity appearances passed in [build 56 validation](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37227547248). Owner reports initial device check works; detailed acceptance remains open. OurAirports: 4,134 airports, 711,086 bytes, public domain. |
| Train | BRouter refused permission. [France audit](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37213117463): 88.6 MB compressed, 273.1 MB installed, 634.7 MB temporary update peak. Owner cancelled Train completely after reviewing the prototype costs. No provider, pack or substitute is being implemented; unused scaffolding removed. |
| History | Store, replay/delete/clear UI, exact-coordinate repeated replay in China and chosen-airport flight replay passed in validation 37152992093. Owner approved populated and empty History screenshots. |
| Settings | Seven groups and full action labels passed UI checks in validation 37152992093. All storage definitions/defaults match `fd7d417`. Owner approved every Settings screenshot. |
| F7/F8 | Share artwork and system symbols committed; identity and no-emoji checks passed in CI. Scan also covers bundled JSON display strings. |
| F9 | Separate bounded time-zone notification change committed; actual-driver checks pass. Owner reports initial build-56 device check works; the broader clock/driving checklist remains open. |
| F10 | Build 54 release provenance and this round's checklist recorded; documentation tracks incomplete acceptance explicitly. |
| F11 | [Build 56](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37227547248) passes 7/8 jobs. Dark Activity passed first attempt; light needed one targeted retry. Only failure was the second simulator launch in a map test; all other nine map/Settings cases passed. Explicit process-exit waits are being validated in [37280386452](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37280386452). Several unchanged-code full passes still required. No outcome assertions removed. |
| Delivery | 3.1.0 build 56 removes the cancelled Train scaffolding; [current iOS 15 launch check](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37213194146) passed. Nothing promoted to `experiment/route-motion`. Full green/repeatability and device checks remain outstanding. No 3.1 Release created. |

## Verification gate

Use the existing full workflow for package identity/signatures/entitlements, migration, motion metadata, session ownership/injection, route models/engine/finish actions, altitude budgets, access/map safety, worldwide search, sharing, map/picker previews, and UI/system controls. Add each phase's required model/fixture/UI tests. Preserve every unrelated assertion. A green package job alone is not a green workflow.

The [device checklist](BUILD-TROLLSTORE.md) covers private injection, clock changes, Snapchat, background/locked operation, sharing and new-mode playback. Initial build-56 device feedback is positive; detailed checks remain open. History and Settings layouts are approved. README.md and docs/readme are maintained separately and have not been edited.

# TrollRoute verification

## Released baseline

**3.0.0, build 54**, released as [v3.0.0](https://github.com/dm2mymcszt-commits/TrollRoute/releases/tag/v3.0.0) on 2026-10-03 from `fd7d417`. `d7f68df` subsequently updates only the separately maintained README and images.

[Build 54 CI](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37047452599) is green on attempt 3. All seven jobs ultimately passed; package/model checks passed on the first attempt. Live Activity first-attempt failures were 4/5 tests in dark and 3/5 in light. Final success does not establish repeatability. [Build 54 package artifact](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37047452599/artifacts/11246230243).

Earlier evidence remains in Git history: [build 53](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/36228389628) for light/dark Live Activity and iOS 17 intent metadata; [build 52](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/36126233477) for import lockout; [iOS 15 launch](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/35969628430). Do not infer exact iOS 17.0 hardware behavior from newer simulator runtimes.

## 3.1 work in progress

| Item | Status and evidence |
| --- | --- |
| Phase 0 | Source/code audit recorded in `ROUND-AUDIT.md`. BRouter operator refused permission; offline feasibility measurement underway. No limited-relation substitute is authorized. |
| Plane | Great-circle/profile/elevation, full engine, all finish/Stop actions and airport/preview/playback UI passed in [validation 37152992093](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37152992093). Its light Live Activity flight scenario passed, but the job later timed out repeating other scenarios. Device acceptance pending. OurAirports: 4,134 airports, 711,086 bytes, public domain. |
| Train | BRouter operator refused permission, as reported by owner on 2026-10-04. No endpoint connected. Measuring metropolitan France offline data/storage/work before another owner decision; audit adds no app behavior. [Request record](docs/BROUTER-PERMISSION-REQUEST.md). |
| History | Store, replay/delete/clear UI, exact-coordinate repeated replay in China and chosen-airport flight replay passed in validation 37152992093. Owner approved populated and empty History screenshots. |
| Settings | Seven groups and full action labels passed UI checks in validation 37152992093. All storage definitions/defaults match `fd7d417`. Owner approved every Settings screenshot. |
| F7/F8 | Share artwork and system symbols committed; identity and no-emoji checks passed in CI. Scan also covers bundled JSON display strings. |
| F9 | Separate bounded time-zone notification change committed; actual-driver checks passed in [validation 37151742655](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37151742655). Device clock/driving Bitmoji checks pending. |
| F10 | Build 54 release provenance and this round's checklist recorded; documentation tracks incomplete acceptance explicitly. |
| F11 | Fresh simulator per original scenario, explicit system consent, one retry of only failed scenarios and distinct attempt evidence. Wrapper success/recovery/persistent/setup-failure checks pass locally. Full CI and several unchanged-code runs still required. No outcome assertions removed. |
| Delivery | 3.1.0 build 55 is the validation candidate on `codex/round31-validation`; nothing promoted to `experiment/route-motion`. Full green CI, Train and device checks remain outstanding. No 3.1 Release created. |

## Verification gate

Use the existing full workflow for package identity/signatures/entitlements, migration, motion metadata, session ownership/injection, route models/engine/finish actions, altitude budgets, access/map safety, worldwide search, sharing, map/picker previews, and UI/system controls. Add each phase's required model/fixture/UI tests. Preserve every unrelated assertion. A green package job alone is not a green workflow.

The [device checklist](BUILD-TROLLSTORE.md) covers private injection, clock changes, Snapchat, background/locked operation, sharing and new-mode playback. All are pending for the eventual 3.1 candidate. History and Settings layouts are approved. README.md and docs/readme are maintained separately and have not been edited.

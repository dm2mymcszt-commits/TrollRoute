# TrollRoute round progress

## Resume

- Source of truth: [ROUND-PLAN.md](ROUND-PLAN.md); detailed evidence and prior failures: [ROUND-AUDIT.md](ROUND-AUDIT.md).
- Branch `experiment/route-motion`, origin `dm2mymcszt-commits/TrollRoute`. Phases0-4 accepted; Phase5 in progress; 6-8 not started.
- Latest verified package: build40 `53fb546`, CI35223404858 build job SUCCESS (all model/live tests, Favorites concurrency, direct Go, migration, signing and previews), route-session UI SUCCESS. Downloaded signatures and shared-endpoint screenshots verified. Phone checklist `216de2c`.
- Phase5 implementation: endpoints/Darwin `cd1d979`, cross-process authority `53e200e`, direct Go `0d4a093`, Favorites `634d0ed` + compiler fix `81aa5a5`. Injection changes still need phone Bitmoji checks.
- Lifecycle harness `c31e6ec`: background/cold/no-replay/edited Favorite PASS. Prior active test found second share consumed <1s but UI retained old fields; build39 first launch timed out. `84e1b3e` build40 fixes revision/reload and stale writes; all lifecycle UI tests PASS in CI35223404858 (`53fb546`), including active <1s and repeated endpoints.
- Map: fresh double-tap and no accidental location taps pass; hold-then-zoom still fails despite build39 touch cancellation change. Native-only baseline zooms. Do not weaken the original test or claim fixed.
- `53fb546` isolation: hold-only reproduces zoom failure; native tap recognizers are prevented by the route hold. `a7bbdb9` fixes XCTest expectation reuse; CI35734494554 comparisons pending.
- `23afaf6` build41 makes route holds unable to prevent native MapKit gestures; native pan can still prevent the hold. No injection change. Original full touch test required; added pan-with-hold-enabled regression to verify native panning still cancels route creation.
- **Next:** verify build41 full touch regression and isolation results; finish Phase5 acceptance before Phase6. Keep long evidence in audit. Delete all three ROUND files in the final commit.

## Decisions already approved

- **Entitlement removal table approved** on 2026-09-13 (exact section 0.5 at `c3ba6b9`, approval recorded `575d61d`). Applied in Phase 2. Keep rows stay; future extension privileges need separate review.
- **Exact GitHub list approved**: rename to TrollRoute; description "Location simulation and route playback for TrollStore."; default `experiment/route-motion`; keep `main`; delete only the 14 tags listed with SHAs in audit; update origin. Executed and verified: new identity/default/description, all 14 tags removed, main preserved.
- **Live Activity destination = current leg endpoint**, including original start on return legs.
- Icon comparison at `1349f7f` explicitly approved on 2026-09-13; ship that exact render, without the rim.
- No GitHub Release authorized or created. No private extension fallback or unreadable-data migration success authorized.
- Injection changes need separate commit and phone Bitmoji test. Physical TrollStore and Dynamic Island behavior must not be claimed from simulator tests.

## Status and commit ledger

| Phase / items | Status | Evidence / next work |
|---|---|---|
| 0.1 baseline facts | Done | `1f7dadf` |
| 0.2 root causes | Done | `cb74fc1`; coverage gap `f586be7` |
| 0.3 identity inventory | Done | `ad85d73`; 431 occurrences / 60 paths in audit |
| 0.4 unused-code proof | Done | `a788fe0` |
| 0.5 entitlement audit | Done, approved | `c3ba6b9`, approval `575d61d` |
| 0.6 architecture | Done | `f2c2a42`; migration detail `bcab51e` |
| 0 acceptance | Done | Audit posted; CI 34759000421 SUCCESS; source unchanged by subsequent documentation commits |
| 1 R1 identity + import | Done; phone import check | `db74fc5`, `9d16061`, `75eba4a`: full CI 34778446157 SUCCESS; signed package verified; read-only fixtures pass |
| 1 R2 repository | Done, `674ee30` | Approved operations executed; verified zero tags/releases; main still bc1e1d3; origin updated |
| 1 R4 icon | Approved and committed | `e6d9569`: exact approved render installed; old icon sources removed. `2b53a12` compares identical pixels across OS; CI 34779276915 icon and app package passed |
| 1 F6 data credits | Done | `db74fc5`: generic About line links exact notices; full CI 34777564932 SUCCESS |
| 1 acceptance | Done | Full CI 34778446157 SUCCESS, downloaded package signing verified. Approved icon built in CI 34779276915; exact pixel check passed. No Release |
| 2 R3 foundation | Done for Phase 2 | Cleanup `d40830b` CI SUCCESS (46s build/package, no Theos). Owner `0cd7066` full CI SUCCESS, including transitions/persistence and all previews |
| 2 F2 injection | Done; phone test required | `c5cbc37` build 9 pushed. Root cause: restart/timezone per sample, unbounded slider inputs. 4 Hz coalescing + immediate jump/pause/arrival + geometry UI. Full CI 34816390584 SUCCESS, including adapter/cancellation tests and all previews |
| 2 F1 altitude | Done; phone check | `13ee72e` build 13: batched terrain, weighted quota, held/provisional refinement, separate prepared/active profiles. Full CI 34849262175 SUCCESS, including actual-owner terrain lifecycle tests |
| 2 acceptance | Done | `13ee72e`: all model/live/UI checks SUCCESS; signed build 13 verified. Build/package 46 s; phone limitations in audit |
| 3 R5, R6 | Done | `f962922`, `91dae7d`, `4273216`, `8b2d8b2`; six real-touch tests and full CI34942207636 SUCCESS |
| 3 R18, R19, R20, R21 | Done; real-location phone check | `b7df278`, `6ee3ce7`, `4273216`; model matrix, preparation workflow and gesture/confirmation tests pass |
| 3 F5 + acceptance | Done | `269fc4a`, `8b2d8b2`; save/edit/persistence tests, visual review and signed build20 pass |
| 4 R11, R12, R13 | Done; phone checks remain | `1976d8a`, `08eb495`; full engine/action matrix and actual Navigation/panel UI pass |
| 4 R15, R16, R17 | Done; phone checks remain | `369ef15`, `b0fdc0b`; both sets, all outcomes, three Stop entry points pass; phone Bitmoji check |
| 4 R14, F3 + acceptance | Done; phone checks remain | `c0962af`, `6d4fa2e`, `e1f3cac`; credits reviewed, moving/paused scrub metadata pass; signed build28; phone Bitmoji check |
| 5 R7, R8, R9, R10, F4 | In progress | R10/ledger full CI29-30; automatic endpoints and approved keys `cd1d979`; shared quota `5188d2c`. Direct Go/lease and lifecycle UI acceptance remain |
| 5 acceptance | In progress | Model tests/package pass; repeated-share UI and held-touch zoom fixes pending; phone checklist recorded |
| 6 R29, R30, R31, R32 | Not started | Registration/access/accuracy status, evidence-based onboarding |
| 6 acceptance | Not started | Status model tests, good/bad screenshots, documented permission decision |
| 7 R22, R23, R24 | Not started | Optional Live Activity, exact content/Stop, two notification toggles |
| 7 R25, R26, R27, R28 | Not started | Accurate explanations, runtime capability, external DynamicCow note, honest testing |
| 7 acceptance | Not started | Intent/state/compatibility tests, native system screenshots, signed widget, iOS 15 launch |
| 8 documentation | Not started | README rewrite; short BUILD guide, migration/release policy/phone checklist |
| 8 regression + delivery | Not started | All Part D + phase checks; version 3.0.0 suggested, increasing build; final per-ID report |
| 8 cleanup | Not started | Delete ROUND-PLAN.md, ROUND-PROGRESS.md, ROUND-AUDIT.md last; no Release |

## Carry-forward constraints

- Three distinct systems: main Stop ends spoofing; Route Stop always asks location outcome; finish action applies at natural arrival.
- Production toolbar/Navigation touch tests and full engine finish/Stop/scrub matrices pass. Physical injection and locked-screen behavior remain phone checks.
- Old favorites/finish destination are WGS-84; recents are map coordinates. Preserve formats and old data. Removing no-container later must not hide newly imported preferences.
- Root helper/dead utilities removed at d40830b. Welcome/checkSandbox/Favorites remain live. New approved icon is opaque PNG; identity localizations updated.
- Source confirms missing share delivery events, not a fixed one-minute timer or a proven scenePhase race. Do not replace with polling.

# TrollRoute 3.1 validation and delivery record

3.1.0 build 56 is delivered on `experiment/route-motion`. Commit `98cda7d` passed three consecutive full workflows on unchanged code before promotion; the final cleanup changes documentation only. The owner cancelled Train entirely after the provider refusal and measured offline assessment. Four modes remain: Walking, Cycling, Driving and Plane. History and Settings layouts are approved. No GitHub Release has been created.

## Acceptance

| Item | Status | Verification and choices |
| --- | --- | --- |
| Phase 6 / Part D | Needs phone test for broader coverage; CI and delivery done | All baseline check commands and named scenarios retained; package, models, engine, migration, injection, altitude, search, sharing, Navigation, map/picker and Activity checks pass in all three full runs. Validated work promoted; initial device smoke pass recorded. Detailed checklist remains open. |
| T1-T4 / Phase 3 | Not done; cancelled by owner | BRouter refused permission. France offline prototype measured 88.6 MB download, 273.1 MB installed and 634.7 MB during replacement. Owner withdrew Train instead of approving country packs. No rail provider, station selection, limited-relation substitute or rail tab ships. |
| P1 | Needs phone test for complete acceptance | Great-circle, date-line, polar, antipodal, long-haul and heading/metadata tests pass; geodesic map rendering captured. Initial build-56 device feedback is positive. No promise about Snapchat's plane appearance. |
| P3 | Needs phone test for complete acceptance | Continuous speed/altitude, exact airport elevations, reduced short-flight ceiling, vertical-rate limits, seeking, live cruise edits, remaining time and reverse-flight tests pass. Initial device feedback positive; detailed short/long-flight checks remain open. |
| P4 | Needs phone test for complete acceptance | Engine verifies seeking, pause/resume, all six finish actions, repeat/return and Route Stop; both Activity appearances' flight scenario passes. Generic long-press/share tests pass. Full Plane entry/background/finish combinations remain on-device checks. |
| Phase 1 / F9 | Needs phone test for complete acceptance | Mode-owned providers/speeds/ranges/icons, lazy cached Plane and ground-mode compatibility tested. Actual driver retains start/jump/stop updates and limits moving updates to meaningful elapsed time/displacement without restarting injection. Initial device feedback positive; extended driving/clock checks remain open. |
| Phase 2 | Needs phone test for broader coverage; implementation done | Flight model/provider, airport picker, geodesic map, playback, altitude override, notifications and Live Activity connected; required unit/engine/UI tests and four Plane captures complete. |
| Phase 0 | Done | Baseline facts checked against fd7d417; airport source and flight architecture/profile evaluated and implemented. Rail source/terms investigation and measured offline assessment closed by owner cancellation. |
| P2 | Done | Nearest-airport and name/city/code search tests pass; selected names/codes are editable. Scheduled-service land airports included; 4,134 records in 234 country codes. Four requested Plane simulator captures obtained. |
| H1 | Done | Successful explicit starts save local entries with endpoints, mode, speed, geometry, airports, finish action, distance/date. Tests cover newest first, deduplication, 50-entry cap and relaunch. Internal repeat/return legs do not add entries. |
| H2 | Done | Saved chosen geometry is restored directly with the same endpoints/mode/speed/finish/airports. Engine tests prove preparation does not start or acquire injection. Four repeated China replays retain exact coordinates and one history entry. |
| H3 | Done | Swipe deletion and confirmed Clear, cancel preservation, relaunch and corrupt-file handling tested. Owner approved populated/empty History captures. |
| S1 / Phase 4 | Done | Seven Settings groups, all existing controls/defaults preserved against fd7d417, route-action labels fully readable. Owner approved every Settings capture. History also accessible from Routes. |
| F7 | Done | Old cheese asset removed; actual packaged extension carries TrollRoute artwork, verified by identity/package checks. |
| F8 | Done | Joystick and favorite toast use SF Symbols; unused emoji strings removed. Automated source/string/JSON/plist scan passes. |
| F10 | Done | BUILD-TROLLSTORE.md and VERIFICATION.md record v3.0.0 from fd7d417, build 54, build 56 delivery and the device checklist. README and its images untouched. |
| F11 / Phase 5 | Done | Three unchanged-code full runs pass, 16/16 jobs each. Activity first attempts: 8/10, 10/10 and 9/10; each of the three failures passed its single permitted retry. All 66 outcome assertions remain. Root-cause fixes and residual simulator limitations are documented below. |

## Suggestion decisions

| Suggestion | Implementation or outstanding choice |
| --- | --- |
| Lazy new modes and cached tabs | New-mode requests occur only for the selected tab; pending requests coalesce and successful/failed results cache for that endpoint generation. Original ground-mode calculation behavior remains. Train was subsequently cancelled and its scaffolding removed. |
| Scheduled airports; name/city/code search | Followed; bundled scheduled-service land airports, with country search also supported. Missing elevations resolve through the existing budgeted free elevation service, with persistent caching. |
| Flight cruise 850 km/h, range 300-1,000 | Followed; live edits ramp smoothly. Short flights may need a lower actual speed, explained in the UI. |
| 11,000 m cruise, lower for short flights | Followed with bounded vertical rates and exact airport heights; profile errors are explicit if elevations/distance cannot support a realistic flight. |
| Flight altitude replaces normal setting | Followed during the flight, explained in the altitude sheet; existing setting applies again after landing. Explicit Stop choices retain their defined captured locations/heights. |
| Train speed, stations and rail provider suggestions | Withdrawn by owner after provider refusal and the measured offline assessment. No substitute; unused scaffolding removed. |
| History saved at start with route details | Followed for explicit successful user starts; internal return/repeat legs do not add entries. Chosen airport IDs/elevations and exact WGS-84 geometry are also preserved. |
| 50 entries, newest first, no duplicate trip | Followed; repeated same endpoints/mode/geometry/airports updates the existing entry and date. Speed and finish edits replace its saved settings. |
| History in Navigation | Followed; also linked from Settings > Routes. Both approved layouts retained. |
| Replay prepares route, user presses Start | Followed; the saved geometry is restored directly, retaining the chosen route without another provider call. No ownership change or location injection on preparation. |
| Swipe delete and confirmed Clear | Followed; cancel preserves entries, store persists across relaunch. History remains local and excluded from backups. |
| Seven Settings groups; shorter explanations | Followed with disclosure rows; storage keys/defaults and conditional options remain guarded against build 54. Owner approved all captures. |
| Bounded retry with first-attempt reporting | Evidence justified fresh simulators and explicit system consent. Only failed scenarios get one retry; setup failures never retry. Original outcome assertions remain. Three full unchanged-code runs now pass; first failures remain visible separately. |
| Version 3.1.0, increasing build | Followed; delivered version is 3.1.0 build 56. No Release. |

## CI and package evidence

All three runs use `98cda7d348315948169595d8ea24d3dc48b4d13a`; no application, test or workflow edits between them.

| Full run | Final jobs | Activity first-pass cases | Cases recovered once |
| --- | --- | --- | --- |
| [37777652110](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37777652110) | 16/16 pass | 8/10 | Dark Notification Centre Pause outcome; light playback compact presentation |
| [37783073505](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37783073505) | 16/16 pass | 10/10 | None |
| [37783078173](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37783078173) | 16/16 pass | 9/10 | Light lock-screen scenario initial widget appearance |

The [verified package](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37777652110/artifacts/11551601415) has SHA-256 `8651d4d9318f63ab96f12d3859126cab37ac4bc1257a93134829a8f894b40c12`. Download the artifact, extract `TrollRoute.tipa`, and install with TrollStore. Local inspection confirms all three binaries' identity/signing/entitlements, airport bundle and share artwork. App/project sources are identical to the owner-tested `315f598` build-56 candidate. Promotion also triggers the ordinary [delivery-branch workflow](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37817851527); its live status is separate from the completed validation gate above.

[iOS 15 launch](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37213194146) passed on runtime 15.5. It predates Train removal/build-number bump; no subsequent app API additions. The owner replied "i checked it works for now" on 2026-10-05 to the driving Bitmoji, long-flight speed/altitude/time-zone and Plane Activity check request. This records an initial smoke pass, without claiming every detailed checklist item was individually checked.

The investigation corrected simulator lifecycle synchronization, unstable activation-point use, widget-local versus screen coordinates, a Bash 3.2 retry-selector bug and a suite budget that could expire before a retry. Fresh simulators isolate each of the original five Activity scenarios in both appearances. Map and Navigation wait for process exit; Navigation also waits for a stable, visible Home-screen anchor. Actual recorded local/global/invalid widget frames are regression-tested. All 19 original workflow check commands and every baseline named scenario remain.

A retained system log measured about 35 seconds between intent receipt and acquisition of its execution assertion; post-system-action outcome checks therefore allow 45 seconds. Only named failed UI scenarios retry once; build/setup failures never retry. Each Activity job has a 30-minute test deadline and five minutes reserved for diagnostics. First-attempt outcomes, screenshots, recordings and system logs remain visible. Persistent failures stay red. No outcome assertion was removed.

Three full green runs establish the requested observed consistency, not a guarantee against every future simulator failure. The recovered dark Notification Centre case in the first run tapped the correct visible centre (109.8, 700.5), but no intent execution appeared in its retained log; its remaining cause is unproven. A separate earlier blank-widget failure logged a missing widget descriptor. These are retained as failures followed by successful bounded retries, not described as clean first-attempt passes. Earlier failed candidates remain in Git/Actions history; the standalone CoreGraphics import error in `6e93408` was fixed in the validated commit.

## Device checklist

Use the complete [on-device checklist](../BUILD-TROLLSTORE.md), including History and Settings, short/long flights and normal-altitude restoration, seek/speed changes in each phase, all finish/Stop/Live Activity choices, long-press/share entry, repeated China replay, Snapchat flight appearance and continued driving Bitmoji behavior. Background/locked travel and existing three-mode behavior remain part of regression acceptance. Train-specific checks are withdrawn.

Changes affecting injection were kept separate: `5113b09` moving time-zone updates, `41c2585` optional profile altitude in the shared adapter, `9f6ce24` flight playback metadata, and `14e41f9` exact WGS-84 History replay. Simulator tests cannot prove private TrollStore injection or Snapchat behavior.

## Data and entitlements

No new entitlements or billing keys. [OurAirports](https://ourairports.com/data/) is the new bundled public-domain source: 4,134 scheduled land airports, 711,086 bytes; provenance and hashes in [AIRPORT-DATA.md](AIRPORT-DATA.md). Nearest/search calculations are local. The existing free [Open-Meteo elevation service](https://open-meteo.com/en/docs/elevation-api), using Copernicus DEM GLO-90 and [CC BY 4.0 API data](https://open-meteo.com/en/licence) under its non-commercial endpoint terms, resolves missing airport heights using TrollRoute identification, the shared request budget, a 30-day/256-airport persistent cache and failure backoff; unavailable elevation never silently becomes zero. Existing Apple directions and OSM cycling attribution remain. No rail service or country pack ships; OSM/Geofabrik measurements are historical research only, documented in [OFFLINE-RAIL-AUDIT.md](OFFLINE-RAIL-AUDIT.md).

## Facts for the separate README maintainer

- 3.1.0 build 56 on experiment/route-motion, validated code 98cda7d, three full green runs and the linked TrollStore package; initial device smoke pass, broader checklist still open.
- Four modes, including airport-to-airport Plane. Train cancelled; do not advertise it as available or forthcoming.
- Editable nearest scheduled airports, local name/city/code search, great-circle line and variable speed/altitude. Cruise setting defaults to 850 km/h, range 300-1,000; short flights may use lower actual speed/altitude. Normal altitude preference resumes after landing.
- Local 50-route History, prepared replay requiring Start, swipe delete and confirmed Clear; no history upload.
- Seven Settings groups, moving time-zone updates, TrollRoute share artwork and symbol-only joystick/favorite toast.
- Public-domain airport source, actual CI retry reporting, detailed device checks and no guaranteed Snapchat plane display.
- TrollStore-only support remains iOS 15.0-16.6.1, 16.7 RC and 17.0; do not identify an owner device model.

README.md and docs/readme were not edited. No GitHub Release was created.

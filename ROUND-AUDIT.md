# Round audit

Audit dated 2026-10-03 against `d7f68df` (app code `fd7d417`). This phase changes documentation only. No entitlement or runtime data source has been added.

## Baseline facts

| Part B | Checked evidence | Result |
| --- | --- | --- |
| Modes and RoutePath | `RouteSimulator.swift`, TravelMode and RoutePath | Confirmed: Walking/Cycling/Driving; provider-independent polyline model. |
| Eager route calculation | `calculateRoutes`, loop over allCases | Confirmed: Apple walking/driving plus routing.openstreetmap.de cycling on every calculation. |
| Constant speed and hard-coded limits | RouteJourney, RouteSpeeds; RouteSimView sliders and increment buttons | Confirmed, 1...500 km/h at all these layers. |
| Altitude | RouteElevation.swift and Altitude.swift | Confirmed: terrain profile, Open-Meteo shared request ledger, fixed Custom altitude. |
| Time zone | LocSimManager.swift, CoreLocationSimulationDriver.inject/stop | Confirmed: notification only on start/jump/stop. Existing Injection test explicitly requires no continuous updates; update that assertion for F9, preserving cadence assertions. |
| Tabs | RouteSimView.swift, RouteModeControls | Confirmed, one HStack over allCases. |
| History | RouteRecentPlaces and repository search | Confirmed: recent places only, no route-run store. |
| Settings | SettingsView.swift and child settings views | Confirmed sections and long explanatory text. Preserve AppStorage keys/defaults, finish destination and access/Live Activity child behaviors. |
| Emoji | JoystickView.swift:22-25; LocSimView.swift:220 | Confirmed four speed labels and favorite toast. Full string-resource scan still required in F8. |
| Share artwork | TrollRouteShare/Media.xcassets/AppIcon.appiconset/Contents.json | Confirmed reference to `slice of cheese.png`. Reuse existing approved TrollRoute artwork. |
| CI | GitHub run 37047452599, attempt 1 logs | Confirmed dark 4/5 failed; light 3/5 failed, build passed. Correction: final conclusion is now SUCCESS on attempt 3, not still red. Does not demonstrate repeatability. |
| Docs/version | Info.plist; BUILD-TROLLSTORE.md; VERIFICATION.md | App is 3.0.0 build 54. Docs still describe 53. `d7f68df` changes only README and docs/readme images. |

Baseline CI: https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37047452599
Local first-attempt logs (ignored): `build/round-baseline-ci-failures.log`.
All seven jobs are finally green, including package/signing and regression checks. This Windows host has no Xcode/Swift runtime; iOS compilation and simulator evidence must come from Actions. Always pass the explicit TrollRoute repository to gh; automatic repository detection picks the upstream Andromeda repository.

## Rail-source feasibility

No provider is approved for production yet. This is a verification gap, not proof that free rail routing is impossible. Phase 3 is paused for the owner's decision; independent phases may proceed.

| Option | Terms and limits | Coverage and reliability | Decision |
| --- | --- | --- | --- |
| BRouter public rail profile | OSM ODbL data; engine MIT. Published profile exists, but no explicit production-app allowance or numerical endpoint quota was established from first-party documentation. Software license alone does not establish hosted-service permission. | Worldwide routing data advertised. Current rail profile includes rail/light rail/narrow gauge and also tram/subway. The deployed profile fetched successfully. Does not itself establish passenger-station coverage or a dependable service contract. | Best technical candidate for a permitted public router, pending operator terms and representative live checks. Do not integrate silently. |
| OpenRailRouting | Open-source GraphHopper-based rail engine; Apache-2.0 repository. Hosted docs advertise routing, but do not establish free app-use limits; generic API docs include authentication/rate-limit errors. Geofabrik's managed service is paid. | Real rail graph and rail-specific profiles. Hosting/import determine coverage. Public map/docs reachable; guessed legacy metadata URL returned 404, which is not evidence the entire router is down. | Self-hosting possible but does not satisfy an unqualified free hosted dependency. Obtain current deployment terms before use. |
| Signal railway router | OSM-based service; no verified public app-use agreement or quota. | Browser fetch returned an Anubis access-denied page. No attempt to bypass protection. | Cannot approve based on current evidence. |
| OSM train-route relations | OSM ODbL. Relations describe mapped services, not an exhaustive routing graph. Any public retrieval service has separate usage limits. | Real member ways can produce track-following paths only if connected and complete. Rails may exist without a relation; relations can contain branches, gaps, nested members and reversed ways. Joining arbitrary members would invent tracks. | Limited-coverage alternative only with owner approval. Missing relation must not be described as proof that no real rail connection exists. |
| Overpass plus local graph search | OSM ODbL. Main public instance gives broad guidance of about 10,000 requests / 1 GB per day, but explicitly identifies non-mapper apps relying on it as a backend as problematic. Quotas are not blanket app-use permission. | Small station queries are possible; whole intercity corridors can be large, incomplete or load-shed (429/504). Downloading tiles to reconstruct the planet is explicitly discouraged. | Do not silently depend on public Overpass for this product. |
| Downloadable OSM extracts plus on-device routing | OSM ODbL, attribution/share-alike for derived databases as applicable. Download host's terms and extract sizes need a separate audit. | Can route over a real graph without live routing calls. Requires data preparation, storage, updates and cross-region connectivity work; footprint not yet measured. | Feasibility expansion offered to owner; no implementation approved yet. |

Primary sources inspected:
- https://brouter.de/brouter/ and https://brouter.de/brouter/profiles2/rail.brf (460-byte deployed profile fetched with identifying User-Agent).
- https://github.com/abrensch/brouter and https://github.com/geofabrik/OpenRailRouting
- https://routing.openrailrouting.org/railway_routing/docs/ and https://www.geofabrik.de/en/data/routing.html
- https://signal.eu.org/osm/
- https://wiki.openstreetmap.org/wiki/Railways and https://wiki.openstreetmap.org/wiki/Relation:route
- https://dev.overpass-api.de/overpass-doc/en/preface/commons.html
- https://www.openstreetmap.org/copyright

Question posted: keep Train pending while obtaining provider permission/limits; investigate downloadable on-device graph; or explicitly accept limited relation coverage. No messages have been sent to providers.

## Station lookup

Preferred data is OSM active passenger stations/halts with stable OSM IDs and multilingual names. Exclude abandoned/disused/proposed facilities and entrances/platforms as duplicate stations. Nearest means geodesic distance in WGS-84, with a stable ID tie-break; selected stations remain visible and editable. Snap to the approved rail graph's station/stop node, never create a straight station-to-track connector and call it track geometry.

Source choice remains coupled to the rail decision: bundle a station index with approved extracts if choosing offline routing, or use an explicitly permitted nearby-station endpoint. OpenRailwayMap's published API supports name/reference station searches, not a documented exhaustive nearest-point lookup. It permits small, public, noncommercial uses with an identifying User-Agent, actively needed requests only, caching, approximately five-second timeouts, and stopping access after 429. No availability guarantee. Its API requires visible OSM data and OpenRailwayMap service credit. Useful for manual selection if approved, but not a substitute for nearest-station correctness.

Reference: https://wiki.openstreetmap.org/wiki/OpenRailwayMap/API

## Airport data choice and measured size

Use bundled OurAirports data (public domain, no accuracy warranty). Include scheduled-service small/medium/large land airports; omit heliports, seaplane bases, closed facilities and unscheduled airfields. Do not require an IATA code: display IATA, else ICAO, else the dataset ident. Search name, municipality, country and codes, case/diacritic insensitive. Resolve the nearest by spherical distance rather than map projection; no network lookup or API key for selection.

Downloaded 2026-10-03 from https://davidmegginson.github.io/ourairports-data/airports.csv using TrollRoute identification.
- Source: 86,158 rows; 12,734,638 bytes; SHA-256 `ff5143921ef72d767402c299a5d868f79166c5c589267aca13dce957c41bd2a2`.
- Selected: 4,134 airports, 234 country codes (865 small, 2,116 medium, 1,153 large).
- Compact preview: 690,014 UTF-8 JSON bytes; 170,580 gzip bytes. Production size may change when storing all search codes and elevation provenance.
- 78 selected airports lack elevation. Keep them searchable. Resolve missing elevations using existing budgeted/cached terrain lookup before a flight can start, retaining the source; if unavailable, clearly request another airport or retry. Never assume zero altitude. Bundle known elevations converted from feet to metres. Pin source hash/date and retain deterministic regeneration instructions.
- Audit download/preview are ignored local files under build/round-audit; no runtime resource has been added in Phase 0.

Sources: https://ourairports.com/data/ and https://ourairports.com/help/data-dictionary.html

## Mode architecture to implement

TravelMode owns provider kind, default speed, allowed speed range, SF Symbol, variable-speed flag and attribution. Existing serialized Walking/Cycling/Driving values and speed preference keys remain unchanged. Proposed Train 130 km/h (1...350), Plane cruise 850 km/h (300...1000); current modes remain 1...500.

Keep the existing three-mode eager calculation/cache behavior. Train and Plane load only on first selection, with endpoint/airport/station identities in the cache key. Tokenize requests to ignore cancelled/stale responses. Cache successful paths separately from errors; explicit retry may refresh failed calculations. Changing speed must not refetch geometry. Five tabs use horizontal scrolling with a minimum readable width and accessible selected state; test small-screen and large-text layouts.

RoutePath carries typed endpoint/provider metadata and an optional flight plan alongside geometry. Preserve the existing ground RouteJourney math. Add a flight-specific journey behind a shared position/speed/altitude/time interface; avoid forcing variable-speed flights into distance divided by cruise speed. Centralize finish actions, pause, seek, return/repeat, notification and Live Activity state around this interface. Ground modes keep their terrain/custom altitude path.

F9 is a separate driver commit. Track the last notified coordinate and a monotonic clock. Notify after meaningful displacement, with a minimum time interval to bound frequency at plane speeds; do not alter injection cadence, restart simulation, or clear/rebuild ownership. Start/jump/stop notifications stay immediate. Test a long moving route and small movements, plus invalid coordinates and relinquish/new ownership. Phone test must confirm the actual clock responds; posting the Darwin notification alone cannot prove iOS timezone behavior.

History stores only local data: stable endpoint identities/names/coordinates, mode, requested speed, route geometry/selection, airport/station choice, finish action, distance and start date. Add at successful user start, not preview, internal return leg or repeat. Deduplicate by trip endpoints/mode/chosen geometry so rerunning moves an entry to the top. Cap at 50; explicit confirmed clear; replay prepares navigation and never invokes Start. Exclude the history file from cloud backup to respect on-device-only storage. Handle corrupt/unknown-version records safely.

## Flight-profile model to implement and verify

Geometry: WGS-84 airport coordinates converted to unit vectors; interpolate on the shortest great-circle arc. Use stable angular distance/atan2, a deterministic tangent for antipodal endpoints, and exact endpoint coordinates. Course comes from the tangent in the local north/east basis. Render MKGeodesicPolyline; simulation uses spherical geometry independent of Mercator. Test date line, near poles, near-coincident and antipodal coordinates; same-airport selection is an explicit unavailable flight.

The profile is a continuous distance-domain envelope with takeoff/climb, cruise and descent/landing. Use smooth transitions for speed and altitude, exact airport elevations at both ends, and zero vertical slope at phase boundaries. Peak altitude is at most 11,000 m for normal elevations, reduced to fit the available climb/descent distance on short flights, but never below either airport. High airports require a peak above local ground. Choose climb/descent lengths to enforce conservative vertical-rate bounds even at the maximum cruise setting; do not let a speed change move the plane vertically. Extreme short/high-elevation pairs need feasibility validation rather than an impossible profile.

Integrate elapsed time over distance using the actual speed envelope, with analytic treatment or well-tested numerical quadrature of zero-speed endpoints. Do not divide by zero at takeoff/landing. Advance by inverse travel-time integration and expose the instantaneous envelope speed. Cruise adjustments change a target speed; bound acceleration and preserve current speed/altitude during the transition. Remaining time must account for this transition as well as future phases. Persist the cruise setting separately from instantaneous speed.

Seeking deliberately relocates along the route, including altitude: evaluate the same profile at the new distance, retain pause state, and recalculate remaining time. During uninterrupted flight and speed adjustments altitude/speed remain continuous. Pause sets injected speed to zero and freezes altitude/progress. Resume restores the phase speed. Returning creates a new profile with swapped airport elevations; repeat resets to the original plan without creating history duplicates. Exact touchdown has arrival elevation and zero speed. Flight altitude overrides Automatic/Custom while flight ownership is active; the altitude sheet explains this. After the route/finish action releases flight ownership, normal altitude preferences apply again.

Tests must validate both mathematics and the production engine: nearest airports; global geometry/course; phase-boundary continuity; short/long-flight altitudes; seeking and speed changes in all phases; bounded climb/descent and acceleration; time integration accuracy; reverse/repeat; metadata speed/course/accuracies; UI/Live Activity/stop/finish actions. Snapshot evidence must come from the iOS simulator. Snapchat appearance and private injection behavior require the owner's TrollStore device.

## CI investigation next steps

First-attempt failures are not exclusively waits for initial system presentation. They include waiting for Companion ended (line 125), restored location after a control (162), Stop after expansion (184), and speed text after expansion (208). Inspect hierarchy and system logs before choosing retries. Host activity-ready only confirms ActivityKit state, not rendered SpringBoard controls. Tests also leave shared SpringBoard/companion state across methods; a failed teardown may contaminate later methods. These are hypotheses, not established root causes.

F11 must preserve every assertion. Prefer deterministic lifecycle/presentation synchronization and test isolation. If evidence establishes simulator infrastructure failure, retry only affected jobs with a small bound, retain all attempt artifacts, and report first-attempt failures separately. Validate several consecutive unchanged-code runs. Do not hide failures with continue-on-error or accept any subset of tests as success.

Additional artifact inspection: first dark artifact `11244988750` downloaded to ignored `build/round-audit/live-first-dark` (272,060,893-byte zip). Its activity-system.log contains 25 `Archive was nil` errors, including compact/minimal/expanded presentations at 18:36:42, 18:37:23, 18:38:45 and 18:39:12 UTC. Tests.log shows Companion End tapped immediately after activation at t=39.93s; Companion ended never appears. That failure exits before Companion termination and can leave a second activity alive for later tests. Later tests press a hard-coded Island coordinate without waiting for the correct compact presentation. This is a concrete isolation/synchronization defect in the harness and a plausible source of cascading failures; validate a cleanup/presentation fix before claiming all failures solved. Metadata-fetch errors also occur; establish whether they are causal by comparison with a passing attempt, not by counting generic log errors.

## Local preparation after audit commit

- Phase 0 committed/pushed as `e477baa`; explicitly dispatched full CI `37113319872` because Markdown-only push is ignored.
- F9 prepared only: actual driver tracks last notification position and monotonic time. Minimum 60 seconds with 5 km displacement, or 300 seconds with 250 m displacement. Immediate start/jump/stop retained. Test suite covers all five mode speeds/date line, no restart and stationary behavior. No actual injection timing changed. Tests require macOS; do not claim executed.
- F7 prepared only: exact existing TrollRoute PNG copied to share AppIcon; old PNG removed; identity checks compare both source files and require compiled extension icon metadata/catalog in package.
- F8 prepared only: joystick SF Symbols and accessibility labels/selection, favorite system pin via AlertKit custom UIImage, removed unused `made by c22dev` catalog entry containing a translated heart. New Python source/catalog/plist scan passes across 55 files and runs in package CI. Verified AlertKit 5.1.8 custom image API from its source.
- F10 prepared only: short BUILD-TROLLSTORE and VERIFICATION replacements, verified released tag target/date, baseline CI rerun caveat and full requested on-device checklist. Do not describe 3.1 as shipped.
- Required workflow clarification posted under A2.2/A3: only CI can compile iOS, yet owner requires build/tests before commit/push. Proposed candidate commits on a temporary validation branch, then move passing items to experiment/route-motion, or direct candidate pushes. Until answered, implementation changes remain local and uncommitted. Do not treat timeout as approval.
- Audit CI on unchanged app code reproduced light Live Activity failure; dark, sharing, route-session and icon checks passed, build/map still running at last check. Phase 0 green-CI acceptance remains unmet. Do not mark the audit complete based only on documentation or the older successful rerun.

## Suggestions and delivery tracking

Planned suggestions accepted: lazy new modes; 850/300...1000 plane speed; 11 km ceiling lowered for short trips; flight altitude override; scheduled airports with searchable names/codes; Train 130/1...350 if approved; history at start, 50 entries/dedup, Navigation button, prepare-only replay, swipe delete/confirmed clear; proposed Settings groups and shorter explanations; version 3.1.0 with increasing build. CI retry suggestion remains conditional on evidence. None are implemented in Phase 0.

README facts at final delivery: five modes only if all shipped; endpoint selection and rail availability constraints; variable flight speed/altitude; history/replay/delete; Settings groups; timezone updates; share/joystick icons; exact version/build, verified CI/package status, data credits and outstanding device checks. README itself and docs/readme remain untouched. No GitHub Release created.

## Owner decisions after first checkpoint (2026-10-03)

Owner approved candidate commits/pushes on a temporary validation branch, with only passing work promoted to experiment/route-motion. Locally prepared F7/F8/F9/F10 are now committed separately. Train remains pending BRouter permission; owner sends the request. Limited relation coverage is rejected. Upon refusal or one week without an answer, measure a one-country offline graph (download/storage/work) and ask again. No permission request sent by Codex.

## Validation and implementation continuation

F9 `5113b09`, F7 `73bbb18`, F8 `b6e3d8f`, F10 `bf31681` were committed separately and pushed on the temporary validation branch. Run `37127628845` on `58a88e2` completed with Live Activity failures (dark Dynamic Island controls and specific-place picker among them). Nothing promoted yet.

F11 `acee882` isolates each of the five original tests in a fresh simulator, waits for compact presentation before expansion, checks stable finite frames before querying hittability, waits for the companion to be foreground and terminates it in defer. Every prior outcome assertion remains. The wrapper retries the full affected suite at most once only when tests actually ran and failed; compile/setup failures do not retry. Per-attempt logs/results/screenshots remain distinct and first-attempt failure is reported in the job summary. Run `37127966618` is validating this; repeatability is not yet established.

Foundation `04c9776` adds five-mode provider/range/icon/default/variable-speed definitions, preserving existing serialized names and preference keys. Existing modes retain 1...500; Train 1...350, Plane 300...1000. New modes request lazily, coalesce pending selections, cache results per endpoint generation and reject old callbacks. Engine tests cover actual request counts, tab caching, speed independence and stale generation rejection. UI tabs scroll at a readable minimum width. Only existing modes are visible until implementation/permission is ready. Run `37128519682` queued at continuation.

Flight model prepared in `Flight.swift`, separate from injection integration: vector great-circle interpolation, explicit antipodal handling, airport lookup/search, continuous altitude and speed envelopes, analytic distance/time transformation and bounded acceleration of live cruise adjustments. Altitude uses smoothstep with conservative maximum 15 m/s climb and 12 m/s descent. Short flights lower both cruise altitude and attainable speed; an infeasible elevation difference is rejected explicitly. The speed envelope has zero endpoints and a finite analytic travel time, eliminating numerical zero-speed stalls. Tests compare ETA with half-second advancement across phases and speed changes, validate rates/continuity and reverse flights, and cover date line, poles, antipodes and long haul. Compilation is pending Actions, not claimed locally.

Production OurAirports bundle generated: 4,134 scheduled land airports, 711,086 bytes, 78 missing elevations; all searchable codes retained. Source and bundle hashes plus regeneration instructions are in `docs/AIRPORT-DATA.md`. This is public-domain data. No flight provider request or location injection has been connected yet.

Flight model/data committed `99e1c15`, validation `37129571636`. Next injection-related commit adds an explicit optional flight altitude to the existing LocationSession/AltitudeController delivery path. Default callers retain identical behavior. Active flights ignore terrain/custom refresh while preserving all horizontal motion metadata. Natural touchdown restores normal settings (Automatic caches the known touchdown elevation); explicit Route Stop preserves its captured height. Stop/relinquish clears the override. Added altitude and session tests; phone verification required. No driver cadence or ownership path is replaced.

Altitude adapter committed `41c2585`. Flight engine integration uses typed FlightPlan metadata in RoutePath/RouteTrack/RouteJourney, spherical position/course, exact profile ETA and actual flight speed in Live Activity state. Preserves original ground math and paused ground Activity display. The shared delivery path now receives the flight altitude; this engine commit is also injection-related and needs phone verification. Reversed legs construct reversed airport profiles; repeat/return retain geodesic overlays. Stop captures flight height at press time and original airport height for Start. Missing-airport elevations use the existing identified, budgeted Open-Meteo lookup with a persistent 30-day/256-entry cache and 60-second failed-lookup cache; no zero substitution. Tests cover actual engine seeking, continuity under speed edits, pause, live snapshots, all six finish actions and every Stop outcome. Flight remains hidden while UI/evidence are unfinished.

Flight engine committed `9f6ce24`. UI candidate exposes Plane, keeps Train hidden pending permission, scrolls selected mode into view, shows editable airport names/codes, searches bundled names/cities/codes, distinguishes target cruise from live speed, explains lower short-flight speed/altitude and altitude override, and uses Fly back to start for flights while preserving existing labels elsewhere. OurAirports public-domain credit appears in preview and playback. Production route-session simulator tests now include airport selection/preview and active flight/pause/return/Stop screenshots. These are tests to run, not screenshots already obtained. The still-queued model-only run may be superseded by the complete candidate, retaining every test.

Plane UI committed `ca4667f`; superseded queued model run `37129571636` cancelled in favor of full run `37130603952`. Flight geometry/profile and airport-elevation tests passed there. App/UI compilation caught `title(flying:)` misplaced in RouteNotificationPreferences rather than RouteFinishAction; fixed separately in `99d7904`. Do not call the complete Plane acceptance passed yet.

History candidate implements a binary Codable archive in local Application Support with backup exclusion on its directory, atomic writes, 50-entry cap, date ordering and deduplication by mode/endpoints/geometry/airport identities (speed and finish settings update an existing trip). Read errors preserve the unreadable archive until explicit Clear. Records are written only after a successful user start; loops/return legs and preview do not record. Replay restores recorded geometry as a cached choice, original endpoints, mode, speed, airport choices and finish settings; it never invokes Start or claims location ownership. Other uncached tabs can calculate on demand. Train records can be retained, but playback remains unavailable while provider permission is pending. Tests cover storage/relaunch/backup/deletion/corruption, engine start/replay and UI clear-confirmation/replay screenshots. History opens from Navigation and Settings. No data is uploaded.

F11 isolated light job `111217090421` in run `37127966618` failed both attempts on different cases: first, Pause in Notification Centre did not expose Resume (SystemTests.swift:164); second, compact Activity content never appeared before the specific-place test (line69). Every remaining assertion was preserved and the bounded retry correctly kept the job red. Logs saved locally in ignored `build/round-audit/isolated-light.log`. Isolation alone is insufficient; inspect the retained system logs/screenshots rather than increasing retries or suppressing failures.

Inspected artifact `11276731574`, first-attempt Notification Centre screenshot `EEB197D2-3413-4A05-A0C1-32B6C16B98CA.png`: the system consent card visibly says Allow Live Activities from Activity QA, with Don't Allow/Allow buttons, while Pause/Stop are already exposed above it. The harness incorrectly treats those controls as ready before granting permission. Add an explicit system-surface consent step after each ActivityKit-ready start, assert the prompt disappears, then return to the original scenario. All existing outcome checks remain and retry count stays two. Missing compact content in the other failure may share this cause; validate rather than assume.

The BRouter draft is ready at `docs/BROUTER-PERMISSION-REQUEST.md`. Official contact: https://groups.google.com/g/osm-android-bikerouting, linked by https://brouter.de/brouter/. Proposed pilot: 20 uncached requests/device/day, minimum 10 seconds, one in flight, 30-day geometry cache, explicit app identification and respect for Retry-After. Public aggregate volume is honestly unknown and specifically asks for terms. Owner sends. Heartbeat `brouter-permission-follow-up` checks from 2026-10-10 10:00 Paris, keyed to the actual send date; it must not assume silence without that date. No provider messages sent.

Run `37131557847`: flight/elevation math, History storage, route-session UI (including Plane and History) and map-workspace UI passed. Package/share/Live Activity apps failed compiling the Settings replay callback in LocSimView; extracted a typed callback in `0f63503`. Consent setup committed `891b974`; handles Original start when re-enabling on a return leg. Revalidation `37151742655`. History screenshots downloaded and visually inspected; owner explicitly approved the populated and empty History layout.

Settings candidate uses seven navigation groups exactly matching the suggested categories; preserves every preference binding and conditional option, with expandable notification/stop/Live Activity explanations. Snapshot generated from released `fd7d417` checks all AppStorage definitions, finish/notification/Live Activity persistence and stop fallback plus map tags. UI tests assert every group and its controls and capture each part. Settings remains awaiting screenshot approval.

Replay review found an actual worldwide bug: WGS-84 saved geometry was converted to GCJ-02 for display and inversely approximated back when constructing the new track. In China this shifts each replay and defeats exact history deduplication. RoutePath now retains the source history entry and uses its original WGS-84 geometry/endpoints; normal provider paths retain their old behavior. Repeated Beijing replay test checks injected start/midpoint and unchanged geometry/entry count. This playback-coordinate change is kept in its own commit and flagged for device testing.

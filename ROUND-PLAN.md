# TrollRoute 3.1: Train and Plane modes, route history, tidier Settings and small fixes

## Part A. Read this first

### A1. Context
- Repository: `dm2mymcszt-commits/TrollRoute`, branch `experiment/route-motion`. Current app code: commit `fd7d417`, version 3.0.0 (build 54), released as `v3.0.0` on 2026-10-03. The branch head `d7f68df` only adds the new README and its images (`docs/readme/`); pull before you start.
- TrollRoute is **TrollStore-only** (iOS 15.0–16.6.1, 16.7 RC, 17.0). The owner has no Mac; GitHub Actions builds the `.tipa`, and the owner tests on a TrollStore device.
- Never name a specific phone model as the owner's device in app text, docs, commit messages or release notes.

### A2. Rules (same as last round)
1. Labels:
   - **[Required]**: confirmed by the owner. Implement exactly.
   - **[Decision]**: the owner's answer to a question. Implement exactly.
   - **[Finding]**: a problem from the final review that the owner wants fixed.
   - **[Suggestion]**: the reviewer's idea. Follow it unless you find a better way that still meets the requirement, and report what you did.
2. If requirements conflict, or something can't work for free on TrollStore/iOS as described, **stop that item and ask me** with the options. Never ship a substitute I didn't approve.
3. **Free only.** No paid APIs and no API keys tied to billing. Follow each free service's usage policy: identify the app, rate-limit, cache.
4. Fix root causes. Preserve all existing behavior I didn't ask to change (Part D). If a test encodes behavior a requirement changes, update the test; all others keep passing.
5. **Don't break the Snapchat driving Bitmoji.** Motion metadata (speed, course, accuracies) must stay consistent in every mode. Changes to how or when locations are injected go in their own commit and are flagged for my phone test.
6. **Never create or publish a GitHub Release** unless I explicitly ask.
7. **Don't edit `README.md` or `docs/readme/`.** The README is maintained separately. In your final report, list the facts the README should mention for this round.
8. No emojis in app text, docs, commit messages or release notes.

### A3. Work method
- Before coding: save this document as `ROUND-PLAN.md`. Create a short `ROUND-PROGRESS.md` (status, decisions, next step) and put long details in `ROUND-AUDIT.md`.
- Commit and push after each item once it builds and its tests pass. Update `ROUND-PROGRESS.md` after each commit.
- **I often hit my usage limit.** When I say continue: re-read `ROUND-PLAN.md` and `ROUND-PROGRESS.md`, check `git status` and `git log`, then continue from the next unfinished step. Don't redo finished items and don't simplify the remaining ones.
- Items waiting for my approval or phone test don't block other work.
- Delete the three `ROUND-*` files in the final commit.

---

## Part B. Facts about the current code (checked at `fd7d417`)
Re-check these in Phase 0.

- **Modes:** `TravelMode` in `TrollRoute/LocSim/RouteSimulator.swift` has three cases: walking, cycling, driving. `RoutePath` is already independent of Apple's `MKRoute` (polyline, distance, expected time, name).
- **Route calculation:** `calculateRoutes` requests routes for **every** mode on each calculation: Apple directions for walking and driving, and the OSM bicycle service for cycling.
- **Speed:** a route moves at one constant speed (`RouteJourney`). The 1–500 km/h limit is hard-coded in several places: `RouteJourney` (init and `changeSpeed`), `RouteSpeeds`, and both sliders in `RouteSimView.swift`.
- **Altitude:** in Automatic mode a route gets a terrain profile (`RouteElevation.swift`, Open-Meteo, with a request budget). Custom altitude is a fixed value.
- **Time zone:** `CoreLocationSimulationDriver` in `LocSimManager.swift` posts the time-zone update only when spoofing starts, on a jump, and on stop. It is never posted while a route moves.
- **Mode tabs:** `RouteModeControls` in `RouteSimView.swift` lays out `TravelMode.allCases` in one row.
- **History:** the app remembers recent *places* (`RouteRecentPlaces`), but it keeps no record of the routes that were run.
- **Settings:** `SettingsView.swift` is one long list with these sections: Map (appearance, style, labels, haptics, tap to set location, and the three long-press options), Location (confirm before stopping spoofing), Location access, Default action when a route finishes, Default action when stopping a route, Notifications, Live Activity, About. Several sections carry long footers.
- **Emojis in the app:** `JoystickView.swift` uses emoji for its speed modes, and `LocSimView.swift` shows a favorite toast titled with a pin emoji.
- **Share action icon:** `TrollRouteShare/Media.xcassets/AppIcon.appiconset/slice of cheese.png` is still the old Geranium artwork.
- **CI:** many runs are marked failed although the `build` job succeeds and uploads the `.tipa`. The failing jobs are simulator UI tests, mostly `live-activity-ui`. Run `37047452599` (`fd7d417`) failed 3–4 of 5 Live Activity tests on its first attempt, on waits for system surfaces.
- **Docs:** `BUILD-TROLLSTORE.md` and `VERIFICATION.md` don't mention build 54.

---

## Part C. Phases

### Phase 0: Feasibility audit (no behavior changes)
1. Confirm the Part B facts.
2. **Train data source.** Evaluate free ways to get a route that follows real railway tracks between two stations, worldwide where OpenStreetMap has rails. Candidates include public OpenStreetMap-based rail routers and OpenStreetMap train-route relations. For each option, give its terms of use, limits, coverage and reliability. **If no option is free, permitted for this use and reliable, stop and ask me before Phase 3.**
3. **Airports.** Choose a free airport dataset that can be bundled (e.g. OurAirports, public domain), decide which airports to include, and report its size.
4. **Stations.** Choose how to find the nearest station to a point (free source, usage policy).
5. Write the flight-profile model and the mode architecture in `ROUND-AUDIT.md`.

**Acceptance:** docs only, CI green, findings and open questions posted to me.

### Phase 1: Mode foundation (shared by Train and Plane)
- Generalize modes so each one defines its route provider, default speed, speed range, icon, and whether its speed varies along the trip. Remove the hard-coded 1–500 limits listed in Part B. Walking, cycling and driving keep their current range.
- [Suggestion] Calculate Train and Plane routes only when their tab is selected, and cache them like the other modes, so free services aren't called on every calculation.
- Mode tabs must stay readable with five modes, including on small screens.
- **F9 [Finding] Time zone on long trips.** The clock must follow the simulated position while a route moves across time zones, in every mode. Post the time-zone update as the trip progresses (for example after a meaningful distance), without restarting the simulation and without posting on every sample.

**Acceptance**
- Existing tests pass, and Part D is unchanged.
- New tests cover per-mode speed ranges, lazy calculation and caching.
- New tests cover time-zone updates along a long route: not posted per sample, and still posted at start, jump and stop.

### Phase 2: Plane mode

**P1 [Required] A realistic plane mode.** The flight follows a real straight path over the globe (the great-circle line between the two airports), and the location data must make it believable that I'm really in a plane.

**P2 [Decision] Airport to airport.** The flight starts at the airport nearest to my chosen start and lands at the airport nearest to my chosen destination.
- Show which airports were chosen (name and code), and let me pick a different one.
- [Suggestion] Use airports with scheduled passenger service, and let me search airports by name, city or code.

**P3 [Required] Realistic flight profile.**
- Speed changes along the flight: takeoff and climb, cruise, then descent and landing. [Suggestion] Default cruise speed about 850 km/h, adjustable from about 300 to 1,000 km/h, including while flying.
- Altitude follows the flight. It starts at the departure airport's ground elevation, climbs to a cruise altitude ([Suggestion] about 11,000 m, lower on short flights), then descends to the arrival airport's ground elevation. Altitude never jumps, and climb and descent rates stay realistic.
- The speed, heading and altitude in the injected location always match the profile. Heading follows the great-circle path.
- [Suggestion] During a flight, the profile's altitude replaces the Automatic or Custom altitude setting; the normal setting applies again after landing. Say so in the altitude sheet.
- Flights that cross the 180° meridian or pass near the poles must work.

**P4 [Required] Everything else keeps working in plane mode:**
- the progress bar (seeking forward and backward) and live speed;
- pause and resume;
- all six finish actions, including flying back and repeating;
- the Route Stop dialog;
- notifications and the Live Activity;
- long press and share-to-route.

Remaining time accounts for the speed profile. Draw the flight as a geodesic line on the map. Don't promise that Snapchat shows a plane; put that on the phone checklist.

**Acceptance**
- Unit tests for the nearest-airport choice and for the great-circle path, including date-line and long-haul cases.
- Unit tests for the profile: continuity of speed and altitude, altitude equal to the airport elevation at both ends, and a reduced cruise altitude on short flights.
- Unit tests for seeking and speed changes inside each phase, remaining-time accuracy, reverse flights, and motion metadata.
- Simulator screenshots: plane tab, airport selection, flight preview, flight in progress.

### Phase 3: Train mode

**T1 [Required] A train mode that follows real railway tracks.**

**T2 [Decision] Station to station.** The trip starts at the station nearest to my chosen start and ends at the station nearest to my chosen destination. Show the chosen stations and let me pick different ones.

**T3 [Required] Free, real tracks only.** Use the source approved in Phase 0. Never draw a straight line and present it as a railway. When no rail route exists between two stations, say so clearly.
- [Suggestion] Default speed 130 km/h, adjustable from 1 to 350 km/h. Terrain altitude works as in the other modes.

**T4 [Required] Everything else keeps working in train mode:** seeking, live speed, pause and resume, finish actions, Route Stop, notifications, Live Activity, long press and share-to-route. Show the data credit the source requires, in the same places as the cycling credit.

**Acceptance**
- Unit tests with recorded fixtures for the nearest-station choice, route decoding, the no-route case, rate limiting and caching.
- One live CI check on a well-known rail connection.
- Simulator screenshots: train tab, station selection, preview, trip in progress.

### Phase 4: Route history and Settings layout

**H1 [Required] Route history.** Add a History screen that lists the routes I have run, so I can run one of them again.
- [Suggestion] Save an entry when a route starts. Store the start and destination (names and coordinates), the travel mode, the speed, the chosen route, the finish action, the distance and the date.
- [Suggestion] Keep the 50 most recent routes. Running the same trip again moves its entry to the top; it doesn't add a duplicate.
- [Suggestion] Open History from a button in TrollRoute Navigation. If you think it belongs somewhere else, propose it with a screenshot.
- History works for every mode, including Train and Plane. It stays on the device and is never sent anywhere.

**H2 [Required] Run a route again.** Choosing an entry lets me redo that route.
- [Suggestion] It opens TrollRoute Navigation with the same start, destination, mode and speed filled in and the routes calculated. I press Start myself; it never starts moving on its own.

**H3 [Required] Delete routes from the history.** I can delete individual routes on the History screen.
- [Suggestion] Swipe to delete, plus a "Clear history" action that asks for confirmation.

**S1 [Required] Tidy the Settings screen.** Settings has grown into one long list; organize it better.
- Keep every existing option, default and behavior. This is a layout change only.
- [Suggestion] Group the options like this:
  - **Map:** appearance, map style, button labels, haptics.
  - **Gestures:** tap to set location with its confirmation; long press to create a route with its two options.
  - **Routes:** default finish action and its place, default action when stopping a route, History.
  - **Safety:** confirm before stopping location spoofing.
  - **Notifications and Live Activity.**
  - **Access:** TrollStore registration, location access, Precise Location.
  - **About.**
- [Suggestion] Shorten the long footers, or move the explanation behind an info row, so the screen is easy to scan.
- **Approval checkpoint:** post simulator screenshots of the new Settings layout and the History screen. Mark them "awaiting approval" and keep working on other phases; finalize after I approve.

**Acceptance**
- Unit tests for the history store: saved at start, newest first, no duplicates, the 50-entry cap, deleting one entry, clearing all, and surviving a relaunch.
- A test that redoing an entry prepares the same start, destination, mode and speed, and never starts the route by itself.
- A test that every Settings key and default is unchanged from 3.0.0.
- Simulator screenshots: the History screen (with entries and empty) and each part of the new Settings.

### Phase 5: Small fixes from the final review
- **F7 [Finding] Share action icon.** Replace the old Geranium artwork in the share extension with TrollRoute's identity, and remove the old file.
- **F8 [Decision] No emojis in the app.** Replace the joystick's emoji speed modes and the favorite toast's pin emoji with system icons, matching the rest of the app. Remove unused leftover strings that contain emoji.
- **F10 [Finding] Docs.** Update `BUILD-TROLLSTORE.md` and `VERIFICATION.md` for build 54 and for this round. Keep them short. Mention that `v3.0.0` was released from `fd7d417`.
- **F11 [Finding] CI status must mean something.** Almost every run is red because of intermittent simulator failures in system-surface tests, even when the package is fine. Find out why those tests fail intermittently and make the result trustworthy: a red run should mean a real problem. Never weaken or remove assertions to get a green run. [Suggestion] If the cause is the simulator itself, retry only the affected jobs a limited number of times, and report first-attempt failures separately from the final result.

**Acceptance**
- The package's share extension carries TrollRoute artwork.
- An automated check finds no emoji in app strings.
- Docs are updated.
- Several consecutive CI runs on unchanged code give the same result.

### Phase 6: Regression and delivery
- Run Part D and every phase's acceptance checks. CI green, `.tipa` built.
- Version [Suggestion]: 3.1.0; the build number keeps increasing.
- Add this round's on-device checklist to `BUILD-TROLLSTORE.md`:
  - History: run two routes, redo one from History, delete one, clear all;
  - Settings: every option is still there and still works after the reorganization;
  - a long flight: altitude, speed, and the clock changing across time zones;
  - a short flight;
  - a train trip;
  - seeking and speed changes in both new modes;
  - finish actions and the Live Activity in both new modes;
  - Snapchat during a flight and during a train trip;
  - the driving Bitmoji still working.
- No GitHub Release. Delete the `ROUND-*` files in the last commit.

---

## Part D. Existing behavior to preserve
Everything delivered in 3.0.0 keeps working:
- safe map taps and long press;
- worldwide search, links, coordinates and plus codes; Favorites in every picker;
- walking, cycling and driving with cached tabs and saved speeds; simulated times, with the shortest route marked Fastest; swap;
- the playback panel with seeking and live speed;
- six finish actions, chosen per trip and changeable mid-route;
- the Route Stop choices and the main Stop confirmation;
- share actions;
- Automatic and Custom altitude;
- notifications and the Live Activity;
- the access overview and the import from Andromeda;
- motion metadata and the Snapchat driving Bitmoji;
- the TrollStore installation check;
- every existing CI test.

## Part E. Final report
- A table: item (P1–P4, T1–T4, H1–H3, S1, F7–F11, phase tasks) → done / partial / not done / needs phone test → how you verified it → choices you made, including every [Suggestion] you followed or replaced. Put partial, not done and waiting items at the top.
- Then:
  - the on-device checklist;
  - any new entitlements or data sources, with their licenses;
  - the README facts to update;
  - confirmation that no GitHub Release was created.

## Owner scope decision (2026-10-04)

After BRouter refused permission and the offline France option was measured, the owner cancelled Train completely. Phase 3 and all Train-specific requirements, tests, screenshots and device checks are withdrawn. Finish the round with Walking, Cycling, Driving and Plane, plus History, Settings and the remaining fixes. Remove unused Train scaffolding; no offline pack or relation-only substitute. All other requirements above remain in force.

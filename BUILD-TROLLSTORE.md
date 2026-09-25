# TrollRoute: build and phone checks

CI uses macOS 15 / Xcode 16.4 on `experiment/route-motion`. Download a successful [build](https://github.com/dm2mymcszt-commits/TrollRoute/actions/workflows/trollstore.yml), extract `TrollRoute.tipa` from **TrollRoute-<version>-<commit>**, and install with TrollStore?s **+** button. Supported versions are listed in [README](README.md).

The new identity installs beside Andromeda. Optional import is offered only while the old app is installed. Once imported values are checked, the old app can be removed. An import error offers Retry or Continue to TrollRoute; it never requires keeping the old app to use TrollRoute.

Build 52 fixes the startup lockout after removing the old app. Install over TrollRoute without uninstalling it. Check that reopening with the old app absent opens the map and keeps existing favorites/settings; repeat after force-closing. The migration regression includes a preferences-save failure followed by uninstall, stale files/journal, and continuing after an optional import error.

Build 53 targets the iOS 17 Live Activity: matching light/dark colors and compatible in-place Pause/Resume/Stop controls. Install over TrollRoute. Check Notification Centre in both appearances: Pause, Resume, Stop, Cancel, then Restore real location. A locked device requires authentication before iOS runs interactive controls.

This round adds the approved icon, shared location ownership, smoother injection and terrain profiles, safer map controls, per-trip finish and Stop choices, direct share actions, access guidance, notifications and Live Activity. [VERIFICATION.md](VERIFICATION.md) records evidence and remaining checks.

## On-device checklist

- [ ] **Phase 1 ? identity/import:** verify the app, icon and share title; compare imported values against Andromeda; confirm old data is unchanged and reopening does not import again.
- [ ] **Phase 2 ? motion/altitude:** test Automatic elevation at 50?500 km/h, reverse legs and arrival; Custom 250 m, `12,5`, negative values and Reset. Recheck search, favorites, joystick, GPX and Snapchat?s driving Bitmoji after the injection changes.
- [ ] **Phase 3 ? map:** default taps do not move you; test enabled tap confirmation and Cancel, double-tap zoom and route selection. Drag below the toolbar to pan the map. Test all long-press confirmation/auto-start combinations, real/spoofed starts, and saving/editing favorites from search and map pins.
- [ ] **Phase 4 ? route session:** exercise all six finish actions, including changes during return legs, without changing Settings defaults. Test both Route Stop choice sets and Cancel; main Stop remains separate. Seek both ways and to 100% while moving/paused, change 50?120?50 km/h, collapse the panel and check cycling credits. Recheck Bitmoji while dragging and after jumps/holds.
- [ ] **Phase 5 ? share:** share Start/Destination while open, backgrounded and closed: Navigation opens with the endpoint and correct source, with no second review or replay. Go there now must move before success while idle/moving/paused/closed, with no old route overwriting it. Check saved altitude. Save an edited favorite without opening TrollRoute and confirm existing favorites remain.
- [ ] **Phase 6 ? access:** System registration is informational; if Settings is missing, follow User-registration instructions, then return to System. Check denied/reduced-accuracy guidance and temporary Precise Location. With While Using access, start a route in the foreground, switch apps/lock, pause/resume and return; check continuous motion and refreshed status after changing permissions.
- [ ] **Phase 7 ? notifications/activity:** test Route finished and Time Sensitive off/on with Focus; a one-time return notifies at both ends, repeats only on first arrival. Enable Live Activity and check its seven fields, speed/seek updates, return-leg destination, Pause/Resume, every Stop choice and specific-place picker. Check iOS 16 app-opening controls and iOS 17 in-place controls where available. Disabling Live Activity must leave the route running.

## Verification limits and releases

CI covers models, signed packaging, live search, touch interactions and real simulator system presentations, plus an actual iOS 15.5 app launch. Physical TrollStore migration, private share opening/injection, background/locked operation, Focus, Snapchat and native Dynamic Island interaction still need the checks above. Earlier simulator widget runs intermittently rendered blank; later runs passed without a production rendering fix, and diagnostic logs were retained. Report any recurrence.

Create a GitHub Release **only when the owner explicitly requests it**. Attach the successful CI `.tipa` and added / changed / fixed notes. No Release was created for this round.

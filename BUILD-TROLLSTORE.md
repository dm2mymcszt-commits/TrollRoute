# TrollRoute: build and device checks

TrollRoute 3.0.0 (build 54) was released as [v3.0.0](https://github.com/dm2mymcszt-commits/TrollRoute/releases/tag/v3.0.0) on 2026-10-03 from `fd7d417`. It clears completed route paths and alternatives. The 3.1.0 (build 55) candidate is on the validation branch. Plane, History and grouped Settings are implemented there; Train remains pending provider permission. Full validation and device checks are incomplete, and this is not a release.

GitHub Actions builds on macOS 15 with Xcode 16.4. Open a successful [package workflow](https://github.com/dm2mymcszt-commits/TrollRoute/actions/workflows/trollstore.yml), download `TrollRoute-<version>-<commit>`, extract `TrollRoute.tipa`, and install it using TrollStore's + button. Install over TrollRoute to retain data. This is TrollStore-only: iOS 15.0-16.6.1, 16.7 RC and 17.0. No Mac is needed for installation.

The app installs beside Andromeda. Optional import is offered while Andromeda is installed. Check imported favorites and settings before removing the old app; reopening TrollRoute must still work. Build 52 fixed the import lockout, build 53 fixed Live Activity contrast and iOS 17 intent compatibility, and build 54 retains both fixes.

## Device checklist for this round

These are acceptance checks for the eventual 3.1 candidate, not claims that unfinished features are available. See [verification](VERIFICATION.md) for current status.

- [ ] History: run two routes, redo one without automatic movement, delete one, clear all with confirmation, then relaunch.
- [ ] Settings: every existing option/default remains present and works after reorganization.
- [ ] Long flight: airport selection, continuous altitude and speed, heading, date-line crossing, and the clock following time zones. Check Automatic and Custom altitude restoration after landing.
- [ ] Short flight: lower cruise altitude, departure/arrival ground elevations and smooth landing.
- [ ] Train: station selection, track-following geometry and a clear error for an unavailable route.
- [ ] Both new modes: seek forward/back while moving and paused; change speed in flight phases and on the train; pause/resume.
- [ ] Both new modes: all six finish actions, changes mid-trip, return/repeat, Route Stop/Cancel, notifications and Live Activity controls.
- [ ] Both new modes: prepare from a long press and from shared Start/Destination places, then check the selected airports/stations before starting. Repeat with each long-press confirmation/auto-start setting.
- [ ] History in China: redo the same saved route repeatedly and confirm its endpoints stay fixed and it remains one history entry.
- [ ] Snapchat during a flight and train trip: record what it displays; a plane or train Bitmoji is not guaranteed.
- [ ] Driving Bitmoji still works after the time-zone/injection-adapter change, including seeking, pause/resume and speed changes.
- [ ] Share action shows TrollRoute artwork. Joystick modes and the favorite toast show system icons.

## Existing behavior to recheck

- Safe map taps and long press, every confirmation/auto-start combination, search/links/coordinates/plus codes, and Favorites in all pickers.
- Walking/cycling/driving: cached tabs and saved speeds, simulated times/Fastest, swap, playback seeking/live speed, finish choices and separate main Stop confirmation.
- Share Start/Destination and Go there now while open/backgrounded/closed; no stale route resumes over a direct move. Save favorites without opening the app.
- Automatic terrain and fixed Custom altitude; access overview, TrollStore installation/registration, location permission and Precise Location; optional import.
- Background/locked travel, Focus and Time Sensitive notifications. Live Activity in both appearances: Pause, Resume, Stop, Cancel, every stop choice and specific-place picker. Locked interactive controls require authentication; disabling Live Activity must leave the trip running.

Simulator checks cannot prove private TrollStore injection, background behavior, clock changes or Snapchat appearance. Record those on the device. Create a GitHub Release only on an explicit owner request; none has been created for the 3.1 work.

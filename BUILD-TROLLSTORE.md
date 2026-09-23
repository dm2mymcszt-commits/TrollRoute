# TrollRoute - TrollStore build

CI uses macOS 15 / Xcode 16.4 on `experiment/route-motion`. Download a successful run's **TrollRoute-<version>-<commit>** artifact, extract `TrollRoute.tipa`, and install with TrollStore's **+** button.

TrollRoute uses `com.dm2mymcszt.trollroute` and installs separately from Andromeda. Keep Andromeda until the migration reports a successful import. Both share actions can appear while both apps are installed. The first launch imports saved places and settings without changing the old data; failed imports remain on a retry screen. Check the summary and imported values before deleting Andromeda. The approved TrollRoute icon is included.

This round is in progress. The repository and application identity have been renamed; map and route refinements are still in progress. Simulator/CI checks cannot verify TrollStore injection, background playback or Snapchat's driving Bitmoji on a physical device.

## Device checks

- Confirm TrollRoute installs separately and its share action has the correct name.
- Check favorites, recents, per-mode speeds, finish action/place, altitude and map settings; verify Andromeda's original data is unchanged before deleting it.
- Recheck static moves, search, joystick, GPX, routes and Snapchat's driving Bitmoji.
- Share a Google Maps place as Start and Destination while TrollRoute is open, backgrounded and closed: it must open Navigation with the endpoint and "From Google Maps", without a second confirmation. Reopening must not replay it.
- Share "Go there now" while idle and during a moving or paused route: confirm the location changes before success, the old route cannot move it back, and TrollRoute stays closed. Check Custom altitude and Automatic altitude, then start another route and recheck Snapchat's driving Bitmoji.
- Edit a shared place's name and save it as a Favorite without opening TrollRoute. Check it in Favorites, Search and both route pickers; confirm existing/imported Favorites remain.

- Check Settings: registration is informational; location access and Precise Location refresh after changing iOS Settings. If the app page is missing, follow the User-registration instructions, then switch back to System.
- Grant While Using the App, start a route, switch apps/lock, pause and resume; verify continuous motion and Snapchat. Check the access notice with permission denied, and the temporary Precise Location request with approximate access.
- Check Route finished off/on, then Time Sensitive off/on during Focus (allow it in iOS notification and Focus settings). Repeating trips notify only on their first arrival; a one-time return notifies at both ends.

## Release policy

Create a GitHub Release only when explicitly requested by the owner. Attach the `.tipa` produced by the successful GitHub Actions run, and write added / changed / fixed notes. No Release is created for this round unless separately requested.

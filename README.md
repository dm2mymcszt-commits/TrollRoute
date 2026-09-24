# TrollRoute

Location simulation and route playback for TrollStore. Set a location, search worldwide, save favorites, import GPX files, or play walking, cycling and driving routes.

## Compatibility and installation

TrollRoute is **TrollStore-only**. It supports iOS 15.0?16.6.1, iOS 16.7 RC (20H18), and iOS 17.0 where [TrollStore](https://github.com/opa334/TrollStore) is supported. Ordinary signing does not provide the private location-simulation privileges it needs.

Download a successful [GitHub Actions build](https://github.com/dm2mymcszt-commits/TrollRoute/actions/workflows/trollstore.yml) from `experiment/route-motion`. Extract **TrollRoute.tipa** from the **TrollRoute-<version>-<commit>** artifact, then install it with TrollStore?s **+** button.

TrollRoute installs separately from Andromeda. On first launch it imports saved places and settings without modifying the old data. Keep Andromeda until the import succeeds and you have checked its summary and your saved values. Both share actions can appear while both apps are installed. An unrelated installed app?s ?Bookmark Location in Geranium? action is not removed.

## Features

- Worldwide search, Google and Apple Maps links, decimal/DMS coordinates, plus codes, favorites and recent places. Search coverage varies by source; approximate matches are marked.
- Walking, cycling and driving routes with cached mode tabs, saved speeds from 1?500 km/h, simulated travel times, and a one-tap start/destination swap.
- Route playback with pause/resume, live speed changes and a draggable progress preview. The trip keeps moving while you preview a seek; releasing jumps to that point.
- Six finish actions, chosen per trip and changeable during playback: stay, go to a saved place, restore real location, loop, return once, or repeat back and forth.
- Separate controls for stopping a route and stopping location spoofing. Route Stop always asks where the location should stay or move; main Stop asks for confirmation by default.
- Long press to prepare a route, with optional confirmation and automatic start. Tap-to-move is off by default.
- Automatic terrain elevation or a saved Custom altitude, including negative values and decimal commas. Route elevation uses a cached terrain profile.
- Share actions to move immediately, open Navigation with a route endpoint, or save an editable favorite.
- A live Settings overview of TrollStore registration, location access and Precise Location.

Route-finished notifications are on by default. Time Sensitive notifications are optional and off by default; iOS notification and Focus settings still apply.

## Live Activity

Live Activity is optional and **off by default**, and requires a supported iOS 16.1+ environment. It shows progress, remaining time and distance, speed, the current leg?s destination, Pause/Resume and Stop. On supported devices it appears on the Lock Screen; a native Dynamic Island provides additional presentations and interaction.

On iOS 17.0, controls act in place and Stop presents the route?s location choices. Choosing a specific place opens TrollRoute?s picker. On iOS 16, controls open the app. Disabling Live Activity or its system presentation does not stop the route.

[DynamicCowTS / DynamicCow](https://github.com/matteozappia/DynamicCowTS) is a separate, optional tool for adding a Dynamic Island presentation externally. It is not bundled; check its own compatibility before using it.

## Build and verification

CI uses macOS 15 and Xcode 16.4 with `ipabuild.sh`. It checks the signed app and extensions, migration, route and location models, worldwide search, map gestures, share delivery, route controls and actual system Live Activity presentations. The app has also launched successfully on an actual iOS 15.5 simulator runtime.

Simulator checks do not establish private location injection, locked-screen operation, Focus delivery, Snapchat behavior or native Dynamic Island interaction on physical TrollStore hardware. See the short [build and phone checklist](BUILD-TROLLSTORE.md) and [round verification report](VERIFICATION.md).

GitHub Releases are created only on the owner?s explicit request, using the `.tipa` from a successful CI run and added / changed / fixed notes. This round produces an Actions artifact; no Release has been created.

## Credits and license

Based on Andromeda by son3ra1n and Geranium by c22dev. GPL-3.0. See [LICENSE](LICENSE).

Data: Apple Maps, ? OpenStreetMap contributors, national address and elevation services. See [data credits and licenses](THIRD-PARTY-NOTICES.md). Google result pages are not scraped and no billing-linked Google API key is required.

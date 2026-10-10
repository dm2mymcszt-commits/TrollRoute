# Map data and software credits

- Apple Maps results use MapKit and Core Location.
- Plane endpoints use a bundled subset of [OurAirports](https://ourairports.com/data/), whose data is public domain. It contains 4,134 scheduled-service land airports; names, cities and codes are searched locally. See [dataset details](docs/AIRPORT-DATA.md). Flight geometry and the speed/altitude profile are calculated on the device. Missing airport elevations use the same budgeted Open-Meteo service below, with a persistent 30-day cache and one-minute failed-lookup cache. No additional entitlement or API key is required.
- OpenStreetMap contributors supply OSM results under the [Open Database License](https://www.openstreetmap.org/copyright), through [Photon](https://github.com/komoot/photon). Its public service permits moderate use, including search as you type. TrollRoute debounces typing, caches repeated queries, and spaces requests by at least 1.25 seconds.
- Bicycle directions use the worldwide [FOSSGIS OSRM service](https://routing.openstreetmap.de/about.html) and OpenStreetMap data. TrollRoute identifies its requests, reserves at least 1.1 seconds between requests, and reuses calculated routes when switching modes or changing speed. Maps displaying bicycle routes include attribution and a map-correction link.
- IGN Geoplateforme supplies address data from the Base Adresse Nationale under its applicable [open-data terms](https://geoservices.ign.fr/services-geoplateforme-geocodage). It is an automatic supplemental source.
- Automatic terrain elevation uses [Open-Meteo](https://open-meteo.com/en/docs/elevation-api) and the worldwide [Copernicus DEM 2021 GLO-90](https://doi.org/10.5270/ESA-c5d3d65), with 90 m grid resolution. Open-Meteo data attribution follows [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); its free endpoint is for personal/non-commercial use. Stationary lookups are spaced by at least 10 seconds, with 60-second failure backoff, a 2,048-sample cache and 45 m reuse radius. Routes request terrain profiles at nominal 90 m spacing, capped at 1,000 points and batched in groups of up to 100 coordinates. Elevation is interpolated along the route; available values are held while later samples load. Eight completed profiles are cached. A shared, locked quota ledger counts coordinates across the app and share extension against minute, hour, day and month limits. Ground elevation is an estimate, not building-floor height. Missing elevation has negative Core Location vertical accuracy; the required numeric placeholder is not a measured zero altitude. Custom altitude uses positive vertical accuracy and preserves all motion metadata.
- `PlaceInput.swift` contains a Swift adaptation of the [Open Location Code algorithm](https://github.com/google/open-location-code), licensed under Apache License 2.0. The adaptation implements decoding and short-code recovery. Upstream test vectors retain that license. See [LICENSE-OpenLocationCode.txt](LICENSE-OpenLocationCode.txt).

No Google result pages are downloaded or scraped. Shared short links are expanded using HTTP redirect headers only; name-only links use the same search sources as typed text.

## Keeper process

The persona-spawn and memory-protection technique in `KeeperNative.m` is adapted from
[TrollSpeed](https://github.com/Lessica/TrollSpeed), `sources/HUDHelper.mm` and
`sources/JetsamHelper.h`, MIT License. The surrounding keeper is implemented for TrollRoute.
Memory command numbers are checked against Apple's published XNU `bsd/sys/kern_memorystatus.h`.

Copyright (c) 2023 Lessica

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

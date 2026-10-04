# Offline Train assessment

BRouter permission was refused, as reported by the owner on 2026-10-04. The public service remains disconnected. This is the requested measurement of an alternative, not approval to change Train's scope or ship it.

## Measured result: metropolitan France

[Audit run 37213117463](https://github.com/dm2mymcszt-commits/TrollRoute/actions/runs/37213117463) passed on commit `5b2bf92`. It downloaded the pinned [Geofabrik France extract](https://download.geofabrik.de/europe/france.html), verified the published MD5, filtered physical railway ways and station objects, and built a prototype SQLite database. MB below means 1,000,000 bytes.

| Material | Measured size | Meaning |
| --- | ---: | --- |
| Original France extract | 5,093,190,405 bytes / 5.09 GB | Build-machine input; not a proposed phone download |
| Rails and station geometry, PBF | 16,776,045 bytes / 16.8 MB | Filtered source; not directly usable by the app |
| Indexed SQLite graph | 273,072,128 bytes / 273.1 MB | Prototype installed database, including spatial and adjacency indexes |
| Gzip database | 88,569,356 bytes / 88.6 MB | Prototype pack transfer size |
| Replacement update peak | 634,713,612 bytes / 634.7 MB | Old database + compressed new pack + extracted new database; excludes app and filesystem overhead |

Filtering took 105 seconds and peaked at 2.19 GB RAM on the Linux builder. Graph creation/compression took 81 seconds and peaked at 662 MB RAM. The complete CI job took 8 minutes 47 seconds. These are build-machine measurements, not iOS runtime memory or routing benchmarks. A phone router must read indexed data with bounded caches instead of loading this Python builder's dictionaries.

The graph contains 1,516,628 rail vertices and 1,541,178 physical segments, from 136,721 ways. Its station table contains 4,002 OSM objects, not 4,002 deduplicated passenger stations: 3,653 nodes, 339 ways and 10 relations. There were no missing node references. The largest undirected component contains 1,451,980 vertices; there are 2,292 components overall. Disconnected islands, yards, separate gauges and incomplete mapping all need honest no-route handling; these counts alone do not establish usable station-to-station coverage.

The database keeps `rail`, `narrow_gauge` and `light_rail` physical geometry, rail tags, station metadata, reverse adjacency and an R-tree. Tram/subway/abandoned/construction ways are not selected as graph edges. It creates no straight gap fillers and does not join tracks just because their lines cross. The fixture verifies those properties and ignores train-route relations as routing input. Station relations are retained only as station metadata.

## Work still needed

This is a storage and connectivity prototype. It does not yet calculate a passenger-compatible route or run inside TrollRoute.

| Work | Deliverable |
| --- | --- |
| Final data pack | Versioned schema, checksums, coverage boundary, metadata/license, reproducible country selection, incomplete-data rejection |
| Railway router | Bounded-memory pathfinding, preserved real track geometry, cancellation, direction/gauge/service policy, explicit no-route outcomes |
| Stations | Deduplicate station objects, resolve areas/relations, assign valid platforms/tracks, nearest-station search and editable picker |
| Pack management | Files import or a separately approved free distribution source, size display, atomic replace/delete, disk-space checks, corruption handling |
| Multiple countries | Match shared OSM identities, resolve overlaps and coverage gaps, test border crossings; never infer worldwide coverage from this France sample |
| App integration | Existing Train speed/terrain profile, preview/seek/pause/finish/Stop, History, long press/share, notifications and Live Activity |
| Verification | Recorded fixtures, disconnected/border cases, real known rail connection, memory/performance measurements, screenshots and device checks |

This is a substantial feature beyond connecting an online provider. Rough planning allowance: 2-3 engineering weeks for a robust first country and app integration, with additional work for multiple-country distribution and border validation. This is an estimate, not measured implementation time or a completion promise. Final storage may differ after station processing and graph optimization; no smaller number is promised.

## Free use and distribution

Geofabrik provides [free OSM extracts](https://download.geofabrik.de/); its [technical notes](https://download.geofabrik.de/technical.html) explain buffered country boundaries. This France file covers metropolitan France, including Corsica, not French overseas territories. The audit made one identified, sequential source download, with bounded network retries; no paid API or key.

OSM data requires [OpenStreetMap attribution](https://www.openstreetmap.org/copyright). A distributed derived pack must carry the [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/) notice and comply with its share-alike and machine-readable access requirements. Keep the transformation scripts and pack available to recipients. App code and dataset licensing are separate. Pyosmium and Osmium are build tools here; neither has been added to the app.

A manual Files-import route avoids depending on a new public routing server or paid hosting. CI can generate selected country packs as downloadable artifacts, with their retention and download-access limitations made explicit. A convenient permanent in-app country catalog needs a separately settled free distribution/update plan. No GitHub Release is required or created by this audit.

## Owner decision required

1. Approve offline country packs, starting with a France pilot and explicit installed-area limits, then expand country coverage and border support. Files import is the simplest initial distribution option. This changes the original immediately-worldwide experience and requires approval before implementation.
2. Keep Train pending and continue completing the other 3.1 work. No relation-only or straight-line fallback.

The measured files were used only in the audit runner. No pack is bundled in TrollRoute, no Train UI is enabled, and no new entitlement was added.

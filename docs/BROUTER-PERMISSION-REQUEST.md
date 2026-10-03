# BRouter permission request

Status: draft for the owner to send; not sent by Codex. Send date and response are not yet known.

## Where to send it

Open https://groups.google.com/g/osm-android-bikerouting, sign in/join if required, and create a new conversation with the subject below. Address it to Arndt Brenschede and the operator of the public brouter.de server. BRouter's official site explicitly directs questions and feedback to this group: https://brouter.de/brouter/ . This is a public group; do not include private device information. Ask for a response from the server operator, rather than treating another user's opinion as permission.

## Subject

Permission request: low-volume rail routing for the free TrollRoute iOS app

## Message

Hello Arndt and BRouter server operators,

I maintain TrollRoute, a free, open-source, noncommercial iOS location-simulation app installed through TrollStore:
https://github.com/dm2mymcszt-commits/TrollRoute

I would like to add a Train mode that simulates a journey along actual railway tracks between two selected stations. This is location simulation, not passenger journey planning, ticketing or railway operations. May the publicly distributed app use your public HTTPS routing endpoint with the rail profile for this purpose, free of charge and without a billing-linked API key?

We would send only the selected station coordinates when the user explicitly calculates a Train route. Playback, seeking, speed changes, pause/resume and cached tab switches would run entirely on the device, with no further routing requests. We would not scrape the network, prefetch routes or query the service for each simulated location sample.

Usage is not measured yet because the feature is not implemented. For an initial owner/testing pilot, I propose at most 20 uncached route calculations per device per day, one request at a time and at least 10 seconds between requests. A small validation check of one known connection would run at most once per day from CI, only if you permit it. These are proposed caps, not a claim about current traffic. For public distribution, I cannot honestly predict the number of installations or guarantee an aggregate cap using only device-side limits; please tell me whether public app use is acceptable and what total usage would require contacting you again or moving to our own routing solution.

Proposed safeguards:
- Identify every request as `TrollRoute/<version> (+https://github.com/dm2mymcszt-commits/TrollRoute)` with the repository as the contact point.
- Request only one route initially; no parallel alternative-route requests.
- Cache successful geometry locally for 30 days, keyed by stations and routing-profile version, and reuse it for repeated trips. Cache no-route results briefly to avoid repeated identical failures. Please tell us if you require a different cache lifetime.
- Honour Retry-After; stop on rate limiting and use bounded backoff on temporary failures, with no server rotation or background retry loop.
- Show visible credit to BRouter and OpenStreetMap contributors, with links and ODbL information, and follow any additional attribution you require.
- Show an unavailable-route error when routing fails, without inventing straight-line railway sections.

Could you confirm the permitted endpoint/profile, usage limits, caching and attribution terms, and whether a small CI check is acceptable? Are there known rail-profile coverage, maximum-distance, station-snapping or service-availability limitations we should explain? The published profile also includes light rail, narrow gauge, tram and subway: would a train-only profile be available or permitted? Station discovery would be handled separately unless you recommend a supported source.

We will keep Train mode unconnected to your service until permission and limits are clear. If this use is unsuitable, please say so; we will investigate offline OSM data instead.

Thank you for your time and for BRouter.

## Follow-up

Tell Codex when this was sent and paste the operator's response. If refused, or unanswered seven days after sending, measure the offline option before asking for the next decision. No limited route-relation fallback is authorized. A chat follow-up is scheduled from 2026-10-10 at 10:00 Europe/Paris; without a known send date it asks for that date rather than assuming the deadline elapsed.

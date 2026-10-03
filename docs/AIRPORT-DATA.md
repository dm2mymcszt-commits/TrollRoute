# Bundled airport data

Source: [OurAirports](https://ourairports.com/data/), public domain, downloaded 2026-10-03. The dataset has no accuracy warranty. No account, billing key or airport API is used by the app.

Included: 4,134 scheduled-service small, medium and large land airports in 234 country codes. Heliports, seaplane bases, closed airports and unscheduled airfields are excluded. Search retains airport names, municipality, country and all supplied codes. Display prefers IATA, then ICAO/GPS/local code, then the dataset identifier.

The UTF-8 bundle is 711,086 bytes. Elevations are converted from feet to metres. 78 airports lack elevation; these require the existing budgeted terrain lookup before starting a flight. Missing elevation must never become an assumed zero.

Regenerate with `python Tools/update-airports.py path/to/airports.csv` after downloading the [source CSV](https://davidmegginson.github.io/ourairports-data/airports.csv). Review changes before replacing the pinned bundle.

- Source SHA-256: `ff5143921ef72d767402c299a5d868f79166c5c589267aca13dce957c41bd2a2`
- Bundle SHA-256: `f2215dc3b15d70b928ffc6d7ca950fce7e79e08f00b6ac112c76195758fc4c43`

"""Regenerate the bundled public-domain OurAirports selection from a local CSV.

Download https://davidmegginson.github.io/ourairports-data/airports.csv first.
Usage: python Tools/update-airports.py path/to/airports.csv
No network access or runtime airport service is required.
"""
import csv
import hashlib
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
airports = []
for row in csv.DictReader(source.read_text(encoding="utf-8").splitlines()):
    if row["scheduled_service"] != "yes" or row["type"] not in {"small_airport", "medium_airport", "large_airport"}:
        continue
    codes = list(dict.fromkeys(row[k] for k in ("iata_code", "icao_code", "gps_code", "local_code") if row[k]))
    airports.append(dict(id=row["ident"], name=row["name"], city=row["municipality"], country=row["iso_country"],
                         codes=codes, latitude=float(row["latitude_deg"]), longitude=float(row["longitude_deg"]),
                         elevation=round(float(row["elevation_ft"]) * 0.3048, 4) if row["elevation_ft"] else None))
airports.sort(key=lambda a: a["id"])
target = Path(__file__).resolve().parents[1] / "TrollRoute" / "Resources" / "Airports.json"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(airports, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8", newline="\n")
print(f"{len(airports)} airports; {target.stat().st_size} bytes; {sum(a['elevation'] is None for a in airports)} missing elevations")
print(f"Source SHA-256: {hashlib.sha256(source.read_bytes()).hexdigest()}")
print(f"Bundle SHA-256: {hashlib.sha256(target.read_bytes()).hexdigest()}")

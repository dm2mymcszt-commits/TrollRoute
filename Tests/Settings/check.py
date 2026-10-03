"""Lock Settings persistence to the released fd7d417 definitions.

The checked-in snapshot comes from that commit, not from the reorganized UI.
This checks keys, stores, defaults and fallback behavior; UI tests check controls.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return re.sub(r"\s+", " ", source[start:end]).strip()


def definitions(read):
    settings = read("TrollRoute/SettingsView.swift")
    values = {"AppStorage": sorted(line.strip() for line in settings.splitlines() if "@AppStorage(" in line)}
    for path, marker in [
        ("TrollRoute/LocSim/RouteFinish.swift", "final class RouteFinishSettings"),
        ("TrollRoute/LocSim/RouteFinish.swift", "struct RouteNotificationPreferences"),
        ("TrollRoute/LocSim/RouteStop.swift", "static func savedDefault"),
        ("TrollRoute/LiveActivity/RouteActivityState.swift", "struct RouteActivityPreference"),
    ]:
        values[marker] = block(read(path), marker)
    # Picker tags are the on-disk representation of these two map settings.
    values["mapTags"] = sorted(re.findall(r'Text\("(?:System|Light|Dark|Standard|Satellite)"\)\.tag\("([^"]+)"\)', settings))
    return values


if __name__ == "__main__":
    expected = json.loads((Path(__file__).with_name("defaults-3.0.0.json")).read_text(encoding="utf-8"))
    actual = definitions(lambda path: (ROOT / path).read_text(encoding="utf-8"))
    assert actual == expected, "Settings persistence changed from released 3.0.0"
    print("PASS: all Settings storage keys, defaults, fallbacks and map tags match 3.0.0 (fd7d417)")

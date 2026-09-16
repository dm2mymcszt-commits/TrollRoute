"""Use production Favorites operations in an isolated, unsigned QA container."""
from pathlib import Path
import sys

source = Path('TrollRoute/LocSim/BookMark/BookMarkHelper.swift').read_text(encoding='utf-8')
# Unsigned QA apps have no production app-group container. Only substitute the
# container dependency; locks, persistence, errors and signal delivery stay real.
assert source.count('FavoritesStore.shared') == 1
source = source.replace('FavoritesStore.shared', 'qaFavoriteStore')
support = r'''
let qaFavoriteDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("FavoritesQA-\(UUID())")
let qaFavoriteStore: FavoritesStore? = FavoritesStore(url: qaFavoriteDirectory.appendingPathComponent("favorites.json"))
func successVibrate() {}
'''
Path(sys.argv[1]).write_text(source + support, encoding='utf-8')

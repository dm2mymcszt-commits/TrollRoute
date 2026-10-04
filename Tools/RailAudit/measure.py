"""Measure a rail graph, not a production route provider.

Every edge is an existing OSM way segment. No gap filling, station connectors,
route relations or geometric crossing joins. Directions/access/gauge are kept
as tags but not enforced by the connectivity diagnostic. Python build memory
is not an estimate of an iOS router's runtime memory.
"""
import collections
import gzip
import hashlib
import json
import math
from pathlib import Path
import resource
import shutil
import sqlite3
import sys
import time

import osmium

RAILS = {"rail", "narrow_gauge", "light_rail"}
STATIONS = {"station", "halt"}


def distance(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 12742000 * math.asin(math.sqrt(min(1, h)))


class Graph(osmium.SimpleHandler):
    def __init__(self, db):
        super().__init__()
        self.db = db
        self.coords = {}
        self.parents = {}
        self.sizes = {}
        self.nodes = []
        self.edges = []
        self.station_counts = collections.Counter()
        self.rail_counts = collections.Counter()
        self.missing_segments = 0
        self.length = 0.0

    def flush(self):
        self.db.executemany('INSERT INTO nodes VALUES (?,?,?)', self.nodes)
        self.db.executemany('INSERT OR IGNORE INTO edges VALUES (?,?,?,?)', self.edges)
        self.nodes.clear()
        self.edges.clear()

    def root(self, node):
        if node not in self.parents:
            self.parents[node] = node
            self.sizes[node] = 1
        while self.parents[node] != node:
            self.parents[node] = self.parents[self.parents[node]]
            node = self.parents[node]
        return node

    def join(self, a, b):
        a, b = self.root(a), self.root(b)
        if a == b:
            return
        if self.sizes[a] < self.sizes[b]:
            a, b = b, a
        self.parents[b] = a
        self.sizes[a] += self.sizes.pop(b)

    def station(self, kind, obj, tags, coord, members=None):
        if tags.get('railway') not in STATIONS:
            return
        self.station_counts[kind] += 1
        self.db.execute('INSERT INTO stations VALUES (?,?,?,?,?,?)',
                        (kind, obj.id, coord[0] if coord else None,
                         coord[1] if coord else None, json.dumps(tags, ensure_ascii=False),
                         json.dumps(members) if members else None))

    def node(self, node):
        if not node.location.valid():
            return
        coord = (node.location.lat, node.location.lon)
        self.coords[node.id] = coord
        self.nodes.append((node.id, round(coord[0]*1e7), round(coord[1]*1e7)))
        self.station('node', node, dict(node.tags), coord)
        if len(self.nodes) >= 10000:
            self.flush()

    def way(self, way):
        tags = dict(way.tags)
        ids = [n.ref for n in way.nodes]
        if tags.get('railway') in RAILS:
            self.rail_counts[tags['railway']] += 1
            self.db.execute('INSERT INTO ways VALUES (?,?)',
                            (way.id, json.dumps(tags, ensure_ascii=False)))
            for a, b in zip(ids, ids[1:]):
                if a not in self.coords or b not in self.coords:
                    self.missing_segments += 1
                    continue
                if a == b:
                    continue
                length = distance(self.coords[a], self.coords[b])
                self.edges.append((a, b, way.id, length))
                self.length += length
                self.join(a, b)
            if len(self.edges) >= 10000:
                self.flush()
        # Representative centroid for size measurement only, not production
        # station snapping. Closed-ring duplicate excluded.
        if tags.get('railway') in STATIONS:
            unique = set(ids)
            coords = [self.coords[i] for i in unique if i in self.coords]
            coord = tuple(sum(c[i] for c in coords)/len(coords) for i in (0, 1)) if coords else None
            self.station('way', way, tags, coord)

    def relation(self, rel):
        self.station('relation', rel, dict(rel.tags), None,
                     [(m.type, m.ref, m.role) for m in rel.members])


def measure(source, target, report):
    started = time.monotonic()
    if target.exists():
        raise ValueError('Use a fresh output path; audit never overwrites a database')
    db = sqlite3.connect(target)
    db.executescript('''
        PRAGMA journal_mode=OFF;
        CREATE TABLE nodes (id INTEGER PRIMARY KEY, lat INTEGER, lon INTEGER);
        CREATE TABLE ways (id INTEGER PRIMARY KEY, tags TEXT);
        CREATE TABLE edges (a INTEGER, b INTEGER, way INTEGER, metres REAL,
                            PRIMARY KEY(a,b,way)) WITHOUT ROWID;
        CREATE TABLE stations (kind TEXT, id INTEGER, lat REAL, lon REAL,
                               tags TEXT, members TEXT, PRIMARY KEY(kind,id)) WITHOUT ROWID;
    ''')
    handler = Graph(db)
    handler.apply_file(str(source))
    handler.flush()
    db.execute('CREATE INDEX edges_reverse ON edges(b,a)')
    db.execute('CREATE VIRTUAL TABLE node_bounds USING rtree(id,minLat,maxLat,minLon,maxLon)')
    db.execute('INSERT INTO node_bounds SELECT id,lat/1e7,lat/1e7,lon/1e7,lon/1e7 FROM nodes')
    db.commit()
    counts = {name: db.execute(f'SELECT COUNT(*) FROM {name}').fetchone()[0]
              for name in ('nodes', 'ways', 'edges', 'stations')}
    assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    dangling = db.execute('''SELECT COUNT(*) FROM edges e
                             LEFT JOIN nodes a ON a.id=e.a LEFT JOIN nodes b ON b.id=e.b
                             WHERE a.id IS NULL OR b.id IS NULL''').fetchone()[0]
    assert dangling == 0
    db.close()
    compressed = target.with_suffix('.sqlite.gz')
    with target.open('rb') as src, compressed.open('wb') as raw:
        with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0, compresslevel=9) as dst:
            shutil.copyfileobj(src, dst)
    result = {
        'scope': 'metropolitan France extract; physical rail/narrow_gauge/light_rail ways',
        'status': 'measurement prototype, not a usable or approved Train provider',
        'source': 'https://download.geofabrik.de/europe/france-261003.osm.pbf',
        'credit': 'OpenStreetMap contributors; ODbL 1.0; extract by Geofabrik',
        'filtered_pbf_bytes': source.stat().st_size,
        'sqlite_bytes': target.stat().st_size,
        'gzip_download_bytes': compressed.stat().st_size,
        'replace_update_peak_bytes': 2*target.stat().st_size + compressed.stat().st_size,
        'counts': counts, 'rail_way_types': dict(handler.rail_counts),
        'station_object_types': dict(handler.station_counts),
        'graph_vertices': len(handler.parents),
        'connected_components_undirected': len(handler.sizes),
        'largest_component_vertices': max(handler.sizes.values(), default=0),
        'top_10_component_sizes': sorted(handler.sizes.values(), reverse=True)[:10],
        'track_geometry_km': handler.length/1000,
        'missing_reference_segments': handler.missing_segments,
        'graph_and_compression_seconds': time.monotonic()-started,
        'linux_builder_peak_rss_bytes': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss*1024,
        'sqlite_sha256': hashlib.file_digest(target.open('rb'), 'sha256').hexdigest(),
        'limitations': [
            'Undirected connectivity only; tags retained but gauge, direction, access and service not enforced.',
            'No station deduplication, platform assignment, routing or gap repair.',
            'Station relation centroids unresolved; way centroids are measurement-only.',
            'Stored coordinates include station/reference-only geometry as well as rail vertices.',
            'R-tree included; iOS runtime memory and routing time not measured.',
            'Country borders and disconnected real networks require explicit product scope.',
        ],
    }
    report.write_text(json.dumps(result, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    return result


if __name__ == '__main__':
    measure(*(Path(arg) for arg in sys.argv[1:4]))

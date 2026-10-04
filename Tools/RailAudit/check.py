"""Audit correctness: geometric crossings must not invent rail connections."""
import gzip
import sqlite3
import tempfile
from pathlib import Path
from measure import measure

with tempfile.TemporaryDirectory() as folder:
    root = Path(folder)
    source = root/'fixture.osm'
    source.write_text('''<osm version="0.6">
      <node id="1" lat="48" lon="2"><tag k="railway" v="station"/><tag k="name" v="A"/></node>
      <node id="2" lat="48" lon="2.02"/>
      <node id="3" lat="47.99" lon="2.01"/>
      <node id="4" lat="48.01" lon="2.01"/>
      <way id="10"><nd ref="1"/><nd ref="2"/><tag k="railway" v="rail"/><tag k="gauge" v="1435"/></way>
      <way id="11"><nd ref="3"/><nd ref="4"/><tag k="railway" v="rail"/><tag k="bridge" v="yes"/></way>
      <way id="12"><nd ref="2"/><nd ref="3"/><tag k="railway" v="abandoned"/></way>
      <relation id="20"><member type="way" ref="10" role=""/><tag k="type" v="route"/><tag k="route" v="train"/></relation>
    </osm>''', encoding='utf-8')
    target = root/'fixture.sqlite'
    result = measure(source, target, root/'metrics.json')
    assert result['counts'] == {'nodes': 4, 'ways': 2, 'edges': 2, 'stations': 1}, result
    assert result['connected_components_undirected'] == 2
    assert result['largest_component_vertices'] == 2
    assert result['missing_reference_segments'] == 0
    assert gzip.decompress(target.with_suffix('.sqlite.gz').read_bytes()) == target.read_bytes()
    with sqlite3.connect(target) as db:
        assert db.execute('SELECT a,b,way FROM edges ORDER BY way').fetchall() == [(1,2,10),(3,4,11)]
        assert '1435' in db.execute('SELECT tags FROM ways WHERE id=10').fetchone()[0]
    print('Rail measurement: crossing isolation, exact physical edges, ignored route relations, tags and archive verified')

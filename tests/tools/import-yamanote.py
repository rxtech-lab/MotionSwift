"""Import OSM relation 1972920/full.json and an optional Overpass `out geom` road layer.

Usage: python3 tests/tools/import-yamanote.py route.json roads.json
Route: https://www.openstreetmap.org/api/0.6/relation/1972920/full.json
Roads: primary/secondary/trunk ways in bbox 35.615,139.685,35.742,139.785.
Only coordinates, station names and source IDs are retained (ODbL-1.0).
"""
import datetime
import json
import math
from pathlib import Path
import sys

output = Path(__file__).resolve().parents[2] / 'Examples/MotionShowcase/Railway'
source = json.loads(Path(sys.argv[1]).read_text())
elements = {(e['type'], e['id']): e for e in source['elements']}
relation = elements['relation', 1972920]
ids = []
for member in relation['members']:
    if member['type'] != 'way' or member['role']:
        continue
    nodes = elements['way', member['ref']]['nodes']
    if ids and ids[-1] == nodes[-1]:
        nodes = nodes[::-1]
    if ids and ids[-1] != nodes[0]:
        raise ValueError('Discontinuous track; refusing to invent a connecting segment')
    ids.extend(nodes if not ids else nodes[1:])
assert ids[0] == ids[-1], 'The full loop must close on the same OSM node'
stations = []
for member in relation['members']:
    if member['type'] != 'node' or member['role'] != 'stop':
        continue
    node = elements['node', member['ref']]
    if any(station['id'] == node['id'] for station in stations):
        continue
    tags = node['tags']
    stations.append(dict(id=node['id'], name=tags['name:en'], localName=tags.get('name:ja', tags['name']),
                         code=tags.get('ref', ''), coordinate=[node['lon'], node['lat']]))
assert len(stations) == 30 and len(set(s['name'] for s in stations)) == 30
start = next(i for i, s in enumerate(stations) if s['name'] == 'Tokyo')
stations = stations[start:] + stations[:start]
start = ids.index(stations[0]['id'])
ring = ids[:-1]
ids = ring[start:] + ring[:start] + [ring[start]]
assert all(s['id'] in ids for s in stations)
assert [ids.index(s['id']) for s in stations] == sorted(ids.index(s['id']) for s in stations)
route = [[elements['node', ref]['lon'], elements['node', ref]['lat']] for ref in ids]

def project(point):
    mercator = lambda lat: math.log(math.tan(math.pi / 4 + math.radians(lat) / 2))
    return [round(460 + (point[0] - 139.685) * 5200, 3),
            round(158 + (mercator(35.742) - mercator(point[1])) / (math.pi / 180) * 5200, 3)]

def path(points):
    return 'M' + ' L'.join(f'{x},{y}' for x, y in map(project, points))

roads = json.loads(Path(sys.argv[2]).read_text())['elements'] if len(sys.argv) > 2 else []
lines = [f'<path d="{path([[p["lon"], p["lat"]] for p in way["geometry"]])}"/>'
         for way in roads if way.get('geometry')]
svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="1080">'
       '<rect width="1440" height="1080" fill="#edf1e9"/>'
       '<g fill="none" stroke="#dce3d7" stroke-width="2">' + ''.join(lines) + '</g></svg>')
(output / 'public/map.svg').write_text(svg)
(output / 'basemap.ts').write_text('// Tokyo OSM primary/secondary/trunk street layer.\n'
                                  + 'export const basemap = "data:image/svg+xml," + encodeURIComponent('
                                  + json.dumps(svg) + ');\n')
data = dict(source='https://www.openstreetmap.org/relation/1972920', license='ODbL-1.0',
            retrieved=datetime.date.today().isoformat(), relationID=1972920, direction='clockwise',
            route=route, stations=stations, roadCount=len(lines))
(output / 'map-data.ts').write_text('// Generated with tests/tools/import-yamanote.py. OSM data, ODbL-1.0.\n'
                                  + 'export const mapData = ' + json.dumps(data, ensure_ascii=False, separators=(',', ':')) + ';\n')
print(f'Imported {len(route)} continuous track points, {len(stations)} stations, {len(lines)} roads')

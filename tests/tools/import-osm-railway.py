"""Import three small OSM XML extracts into the bundled, reproducible railway example.

Usage: python3 tests/tools/import-osm-railway.py /path/to/west.osm /path/to/central.osm /path/to/east.osm
Source: https://www.openstreetmap.org/api/0.6/map?bbox=west,south,east,north
Bounds: 114.15/114.165/114.18/114.195, south 22.274, north 22.291.
OSM data is ODbL; no user or changeset metadata is retained.
"""
import datetime
import html
import json
import math
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[2]
output = root / "Examples/MotionShowcase/Railway"
elements = {}
for filename in sys.argv[1:]:
    for element in ET.parse(filename).getroot():
        elements[element.tag, element.get("id")] = element


def tags(element):
    return {tag.get("k"): tag.get("v") for tag in element.findall("tag")}


def coordinate(ref):
    node = elements["node", ref]
    return [float(node.get("lon")), float(node.get("lat"))]


def project(point):
    x = 40 + (point[0] - 114.15) / 0.047 * 880
    mercator = lambda lat: math.log(math.tan(math.pi / 4 + math.radians(lat) / 2))
    y = 128 + (mercator(22.291) - mercator(point[1])) / (math.radians(0.047)) * 880
    return [round(x, 2), round(y, 2)]


def path(points):
    return "M" + " L".join(f"{x},{y}" for x, y in map(project, points))


relation = elements["relation", "4432666"]  # MTR Island Line, eastbound
route_ids = []
stations = []
for member in relation.findall("member"):
    key = member.get("type"), member.get("ref")
    if key not in elements:
        continue
    element = elements[key]
    if member.get("type") == "node" and member.get("role", "").startswith("stop"):
        point = coordinate(member.get("ref"))
        if 114.15 < point[0] < 114.195 and 22.274 < point[1] < 22.291:
            info = tags(element)
            stations.append({"id": int(member.get("ref")), "name": info["name:en"],
                             "localName": info.get("name:zh", ""), "coordinate": point})
    if member.get("type") == "way" and not member.get("role"):
        ids = [node.get("ref") for node in element.findall("nd")]
        if route_ids and route_ids[-1] == ids[-1]:
            ids.reverse()
        if route_ids and route_ids[-1] != ids[0]:
            raise ValueError("Route extract is not continuous; refusing to invent a connecting segment")
        route_ids.extend(ids if not route_ids else ids[1:])
start, end = (route_ids.index(str(station["id"])) for station in (stations[0], stations[-1]))
route = [coordinate(ref) for ref in route_ids[start:end + 1]]
assert len(stations) == 7 and len(route) > 50

parks, roads, coast = [], [], []
road_names = {}
for (kind, osm_id), element in elements.items():
    if kind != "way":
        continue
    info = tags(element)
    points = [coordinate(node.get("ref")) for node in element.findall("nd") if ("node", node.get("ref")) in elements]
    if len(points) < 2:
        continue
    if info.get("leisure") in ("park", "garden", "pitch") and len(points) > 3:
        parks.append(f'<path d="{path(points)} Z" fill="#cdddc3"/>')
    highway = info.get("highway")
    if highway in ("primary", "secondary", "tertiary", "residential", "trunk", "unclassified"):
        width = 3 if highway in ("primary", "trunk") else 1.5
        roads.append(f'<path d="{path(points)}" stroke="#ffffff" stroke-width="{width}"/>')
        name = info.get("name:en")
        if name in ("Hennessy Road", "Gloucester Road", "Harcourt Road", "Connaught Road Central", "King\'s Road"):
            road_names.setdefault(name, points[len(points) // 2])
    if info.get("natural") == "coastline":
        coast.append(points)

# Stitch shoreline pieces before filling the harbour above the real coastline.
while len(coast) > 1:
    joined = False
    for first in range(len(coast)):
        for second in range(first + 1, len(coast)):
            a, b = coast[first], coast[second]
            if a[-1] == b[0]:
                combined = a + b[1:]
            elif b[-1] == a[0]:
                combined = b + a[1:]
            elif a[-1] == b[-1]:
                combined = a + b[-2::-1]
            elif a[0] == b[0]:
                combined = a[::-1] + b[1:]
            else:
                continue
            coast[first] = combined
            coast.pop(second)
            joined = True
            break
        if joined:
            break
    if not joined:
        break
shore = max(coast, key=lambda points: max(p[0] for p in points) - min(p[0] for p in points))
if shore[0][0] > shore[-1][0]:
    shore.reverse()
shoreline = path(shore)
sea = f'{shoreline} L{project(shore[-1])[0]},-200 L{project(shore[0])[0]},-200 Z'
labels = []
for name, point in road_names.items():
    x, y = project(point)
    labels.append(f'<text x="{x}" y="{y}" font-size="9" fill="#868c86">{html.escape(name)}</text>')
svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="960" height="540">'
       '<rect width="960" height="540" fill="#ecebe2"/>'
       f'<path d="{sea}" fill="#b9d8dc"/>' + ''.join(parks) +
       '<g fill="none" stroke-linecap="round" stroke-linejoin="round">' + ''.join(roads) + '</g>' +
       '<g font-family="Helvetica Neue, sans-serif">' + ''.join(labels) + '</g></svg>')
(output / "public").mkdir(parents=True, exist_ok=True)
(output / "public/map.svg").write_text(svg)
(output / "basemap.ts").write_text("// Generated from the real OSM streets and coastline.\n"
                                   + "export const basemap = 'data:image/svg+xml,' + encodeURIComponent("
                                   + json.dumps(svg, ensure_ascii=False) + ");\n")
data = {"source": "https://www.openstreetmap.org/relation/4432666", "license": "ODbL-1.0",
        "retrieved": datetime.date.today().isoformat(), "relationID": 4432666,
        "route": route, "stations": stations, "roadCount": len(roads)}
(output / "map-data.ts").write_text("// Real OpenStreetMap extract; regenerate with tests/tools/import-osm-railway.py.\n"
                                    + "export const mapData = " + json.dumps(data, ensure_ascii=False, separators=(",", ":")) + ";\n")
print(f"Imported {len(roads)} roads, {len(route)} railway points and {len(stations)} stations")

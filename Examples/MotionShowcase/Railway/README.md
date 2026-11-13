# OpenStreetMap · Island Line

Real OpenStreetMap geography, rendered natively as a Remotion composition. Roads,
parks and coastline form the map; the blue animated route follows the actual
eastbound railway through Sheung Wan, Central, Admiralty, Wan Chai, Causeway Bay,
Tin Hau and Fortress Hill. Station labels use OSM English and Chinese names.

The train advances by distance along the track. It is an illustrative 12-second
journey, not a timetable or a driving route. Map and labels share a Web Mercator
projection. Preview, editing and export use the same bundled data with no network
dependency or tile-service API key. The sample is a geographic snapshot, not a
live map browser; no synthetic streets or straight-line station connections are used.

Data retrieved 2026-11-13 from OpenStreetMap API 0.6, bounded extracts:

- `114.15,22.274,114.165,22.291`
- `114.165,22.274,114.18,22.291`
- `114.18,22.274,114.195,22.291`

Route: [OSM relation 4432666](https://www.openstreetmap.org/relation/4432666).
Data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright),
available under the [Open Database License](https://opendatacommons.org/licenses/odbl/1-0/).
Attribution remains visible in every rendered frame and export. The included
`map-data.ts` is the derived route/station dataset; `public/map.svg` is the vector
basemap and `public/map.png` its prepared raster. Both renderers use the same PNG
to avoid differences in antialiasing thousands of street edges and labels. The
prepared image includes the drawn route and station labels; train positioning and
the journey progress indicator remain frame-driven native elements.

To update, save those three XML responses from
`https://www.openstreetmap.org/api/0.6/map?bbox=…`, then run:

```sh
python3 tests/tools/import-osm-railway.py west.osm central.osm east.osm
node tests/tools/generate-railway-basemap.mjs
```

The importer rejects discontinuous railway geometry. Review regenerated maps and
station names before committing. Raw OSM user and changeset metadata is discarded.
Native rendering/staging is covered by `RailwayShowcaseTests`; route/projection and
portable compilation checks run with the ordinary Node suite in push CI. The real
map composition also runs against Remotion in `make maps-visual`, on CPU and GPU.

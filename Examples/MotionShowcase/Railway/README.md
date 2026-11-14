# Yamanote Line · Complete clockwise loop

A 50-second 16:9 (`1920×1080`) continuous journey through all 30 stations on Tokyo's
Yamanote Line, starting at Tokyo, gliding clockwise through Shinagawa, Shibuya,
Shinjuku, Ikebukuro and Ueno without intermediate stops, and returning from Kanda
to Tokyo. Includes Takanawa Gateway. All 30 stations are geographic markers on an
OpenStreetMap tile map, with bilingual Japanese and English labels on major hubs
and nearby stations along the active leg.

The train follows the real, continuous outer-loop railway geometry from
[OpenStreetMap relation 1972920](https://www.openstreetmap.org/relation/1972920).
The 904-point track is closed on the same node; station names and coordinates come
from its 30 unique stop positions. Track and roads use the same Web Mercator projection.
Station order can also be checked against [JR East's numbering map](https://www.jreast.co.jp/e/downloads/pdf/numbering_e.pdf).

The train travels continuously by distance along the railway polyline: 2 seconds
before departure at Tokyo, 46 seconds of uninterrupted clockwise travel around all
30 stations, and 2 seconds upon returning to Tokyo. The JR East-inspired `JY` HUD
cards show the approaching station badge (`JY01`–`JY30`), current leg, visited
station count and loop progress. Backward seeks and repeated frames compute the
same state.

The camera starts with the full loop in view (zoom 13), smoothly zooms in over
3 seconds, then follows the train at zoom 15. At the final return to Tokyo it
zooms out to the whole loop again. The `<MapView>` camera, zoom, provider, style
and markers can also be panned, overridden or keyframed directly in the MotionSwift
editor.

The composition ID remains `IslandRailway` for existing navigation. The showcase
creates a fresh `Yamanote-v3` working copy, preserving earlier edited examples.
`artwork.ts` and `public/map.png` retain the previous static overview as a reference;
they are not used by the playback composition.

Data retrieved 2026-11-14. © OpenStreetMap contributors, ODbL-1.0; attribution is
visible throughout. Regenerate reference provenance after updating `route.ts` or
`artwork.ts`:

```sh
python3 Tests/tools/import-yamanote.py route.json roads.json
node Tests/tools/generate-railway-basemap.mjs
```

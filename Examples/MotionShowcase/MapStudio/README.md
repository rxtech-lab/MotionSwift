# Map Studio

The map studio, tile view, Apple Maps view and Atlas use San Francisco International
Airport (SFO). Cameras, routes, markers and their keyframes remain editable.
The separate [railway study](../Railway/README.md) follows the entire Yamanote Line
in Tokyo through all 30 stations, zooming into a street map and following the train.

SFO tiles and railway routes are fetched on first use and cached on disk.
Attribution remains visible in every frame. Apple Maps falls back to OpenStreetMap
where MapKit is unavailable. Existing edited copies are preserved.

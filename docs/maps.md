# Maps (`@motionswift/map`)

`@motionswift/map` draws deterministic slippy maps for video: provider raster tiles in Web
Mercator, with routes and markers on top. Every prop is editable in the [visual editor](editor.md#maps).

```tsx
import {MapMarker, MapRoute, MapView} from '@motionswift/map';

export const Journey = () => (
  <MapView center={[-122.3860, 37.6220]} zoom={13} provider="apple" mapStyle="standard">
    <MapRoute from={[-122.3920, 37.6160]} to={[-122.3899, 37.6003]} mode="railway" progress={0.5} />
    <MapMarker coordinate={[-122.3920, 37.6160]} label="SFO International Terminal" />
  </MapView>
);
```

Coordinates are `[longitude, latitude]`. `MapView` fills the composition unless `width`/`height`
are given. A working example is `Examples/MotionShowcase/MapStudio` (Motion Studies → Map studio).

## `<MapView>`

| Prop | Default | Notes |
|---|---|---|
| `center` | `[0, 0]` | Camera center. |
| `zoom` | `2` | 0–22, fractional values are smooth. |
| `bearing` | `0` | Degrees clockwise; the bearing direction points up. |
| `provider` | `openstreetmap` | `openstreetmap`, `apple`, `mapbox`. |
| `mapStyle` | provider's first | See providers below. |
| `saturation`, `brightness` | `1` | Tile color multipliers, 0–2. |
| `attribution` | `bottom-right` | Corner of the provider attribution, which is always drawn. |

## Providers

| Provider | Styles | Requirements |
|---|---|---|
| `openstreetmap` | `standard`, `humanitarian`, `topographic` (OpenTopoMap), `light`, `dark` | None. `light`/`dark` are filtered `standard` tiles. |
| `apple` | `standard`, `muted`, `dark`, `satellite`, `hybrid` | Apple platforms: each tile is an `MKMapSnapshotter` image of the exact tile rect. |
| `mapbox` | `streets-v12`, `outdoors-v12`, `light-v11`, `dark-v11`, `satellite-v9`, `satellite-streets-v12` | An access token: `MAPBOX_ACCESS_TOKEN`, `MOTIONSWIFT_MAPBOX_TOKEN`, or the editor's Map Settings. |

When a provider is unavailable (Apple Maps off Apple platforms, Mapbox without a token) the map
falls back to OpenStreetMap, keeping light/dark looks, and the editor shows a note. The
attribution always names the provider that actually drew the tiles. Follow each provider's terms
for your use (for example the [OpenStreetMap tile usage policy](https://operations.osmfoundation.org/policies/tiles/)
and Apple's and Mapbox's terms); heavy production use should use your own tile server or account.

## `<MapRoute>`

| Prop | Default | Notes |
|---|---|---|
| `from`, `to` | required | Endpoints; `via` adds waypoints. |
| `mode` | `straight` | `straight` (great circle), `arc` (flight arc), `driving`, `cycling`, `walking` (OSRM at routing.openstreetmap.de), `railway`, `subway`, `tram` (shortest path over OpenStreetMap tracks from the Overpass API). |
| `progress` | `1` | Drawn fraction; keyframe it to animate the journey. Progress follows distance along the route. |
| `color`, `outlineColor`, `width`, `markerSize`, `dashed` | | Line style and the moving head marker (`markerSize={0}` hides it). |

## `<MapMarker>`

`coordinate`, `color`, `size`, `label`, `labelColor`.

For custom overlays, `useMap()` returns the enclosing camera with `project(coordinate)` and
`unproject(point)` in map pixels.

## Determinism, caching and offline use

Inside MotionSwift, tiles load through the `motionmap://tile/{provider}/{style}/{z}/{x}/{y}`
image scheme and routes through the host. Both are cached on disk in
`Caches/MotionSwift/Maps` (override with `MOTIONSWIFT_MAP_CACHE`) the first time they are fetched,
so later previews, exports and offline sessions draw identical frames.

- **Previews** wait up to three seconds for a route, then draw a straight placeholder while the
  route resolves in the background; the player re-renders when it arrives.
- **Exports and the CLI** wait for routes (time spent on map services does not count against the
  frame's async deadline). Failed lookups draw a straight line and report the reason in the editor.
- **Offline mode** (`MOTIONSWIFT_MAP_OFFLINE=1`) uses the cache, draws neutral placeholder tiles
  for missing ones and makes no network requests. Tests use it.

Outside MotionSwift (a browser), OpenStreetMap tiles load over HTTPS, other providers fall back to
OpenStreetMap, and network route modes draw straight lines.

import type {CSSProperties, ReactElement, ReactNode} from 'react';

/** `[longitude, latitude]` in degrees (WGS 84). */
export type Coordinate = [number, number];
export type MapProvider = 'openstreetmap' | 'mapbox' | 'apple';
export type MapRouteMode = 'straight' | 'arc' | 'driving' | 'cycling' | 'walking' | 'railway' | 'subway' | 'tram';
export type MapAttributionPosition = 'bottom-right' | 'bottom-left' | 'top-right' | 'top-left';

export interface MapViewProps {
  /** Camera center. Default `[0, 0]`. */
  center?: Coordinate;
  /** Web Mercator zoom, 0–22 (fractional values are smooth). Default 2. */
  zoom?: number;
  /** Clockwise map rotation in degrees; the bearing direction points up. Default 0. */
  bearing?: number;
  /**
   * Tile provider. `apple` uses MapKit on Apple platforms and `mapbox` needs an access token;
   * both fall back to OpenStreetMap when unavailable. Default `openstreetmap`.
   */
  provider?: MapProvider;
  /**
   * Provider style: openstreetmap `standard | humanitarian | topographic | light | dark`,
   * mapbox `streets-v12 | outdoors-v12 | light-v11 | dark-v11 | satellite-v9 | satellite-streets-v12`,
   * apple `standard | muted | dark | satellite | hybrid`.
   */
  mapStyle?: string;
  /** Tile saturation multiplier, 0–2. Default 1. */
  saturation?: number;
  /** Tile brightness multiplier, 0–2. Default 1. */
  brightness?: number;
  /** Corner of the provider attribution, which is always drawn. */
  attribution?: MapAttributionPosition;
  backgroundColor?: string;
  /** Defaults to the composition size. */
  width?: number;
  height?: number;
  style?: CSSProperties;
  children?: ReactNode;
}

export interface MapRouteProps {
  from: Coordinate;
  to: Coordinate;
  /** Intermediate waypoints, in order. */
  via?: Coordinate[];
  /**
   * `straight` (great circle) and `arc` are computed locally. `driving`, `cycling` and `walking` follow
   * roads (OSRM); `railway`, `subway` and `tram` follow OpenStreetMap tracks. Default `straight`.
   */
  mode?: MapRouteMode;
  /** Drawn fraction of the route, 0–1; keyframe it to animate the journey. Default 1. */
  progress?: number;
  color?: string;
  /** Line width in pixels. Default 5. */
  width?: number;
  /** Casing color, or `none`. Default white. */
  outlineColor?: string;
  /** Diameter of the moving head marker; 0 hides it. Default 14. */
  markerSize?: number;
  dashed?: boolean;
}

export interface MapMarkerProps {
  coordinate: Coordinate;
  color?: string;
  size?: number;
  label?: string;
  labelColor?: string;
}

export interface MapCamera {
  zoom: number;
  bearing: number;
  width: number;
  height: number;
  center: Coordinate;
  /** Composition pixel of a coordinate inside the map. */
  project(coordinate: Coordinate): [number, number];
  unproject(point: [number, number]): Coordinate;
}

export declare function MapView(props: MapViewProps): ReactElement;
export declare function MapRoute(props: MapRouteProps): ReactElement;
export declare function MapMarker(props: MapMarkerProps): ReactElement;
/** The enclosing map's camera, for custom overlays. */
export declare function useMap(): MapCamera;
export declare function projectCoordinate(coordinate: Coordinate,
  options: {center?: Coordinate; zoom?: number; bearing?: number; width: number; height: number}): [number, number];
export declare function resolveProvider(provider?: string, style?: string): {
  provider: MapProvider; style: string; note: string | null; native: boolean;
};
export declare const MAP_PROVIDERS: Record<MapProvider, {
  label: string;
  styles: Record<string, {label: string; maxZoom: number; attribution: string}>;
}>;

import {mapData} from './map-data';

export const project = ([longitude, latitude]: number[]) => {
  const mercator = (lat: number) => Math.log(Math.tan(Math.PI / 4 + lat * Math.PI / 360));
  return [
    460 + (longitude - 139.685) * 5200,
    158 + (mercator(35.742) - mercator(latitude)) / (Math.PI / 180) * 5200,
  ];
};

type PrecomputedTrack = {
  route: number[][];
  stations: Array<(typeof mapData.stations)[number] & {point: number[]}>;
  distances: number[];
  stationDistances: number[];
};

const scope = globalThis as {__msYamanoteTrack?: PrecomputedTrack};
if (!scope.__msYamanoteTrack) {
  const projectedRoute = mapData.route.map(project);
  const projectedStations = mapData.stations.map(station => ({...station, point: project(station.coordinate)}));
  const cumulative: number[] = new Array(projectedRoute.length);
  cumulative[0] = 0;
  for (let i = 1; i < projectedRoute.length; i++) {
    cumulative[i] = cumulative[i - 1] + Math.hypot(
      projectedRoute[i][0] - projectedRoute[i - 1][0],
      projectedRoute[i][1] - projectedRoute[i - 1][1],
    );
  }
  const stops = projectedStations.map(station => {
    const index = projectedRoute.findIndex(point => Math.hypot(point[0] - station.point[0], point[1] - station.point[1]) < 0.01);
    if (index < 0) throw Error(`Station is missing from the track: ${station.name}`);
    return cumulative[index];
  });
  scope.__msYamanoteTrack = {
    route: projectedRoute,
    stations: projectedStations,
    distances: cumulative,
    stationDistances: stops,
  };
}

export const route = scope.__msYamanoteTrack.route;
export const stations = scope.__msYamanoteTrack.stations;
export const distances = scope.__msYamanoteTrack.distances;
export const stationDistances = scope.__msYamanoteTrack.stationDistances;
export const totalDistance = distances[distances.length - 1];
export const path = (points: number[][]) =>
  points.map(([x, y], index) => `${index ? 'L' : 'M'}${x.toFixed(2)},${y.toFixed(2)}`).join(' ');

function segmentAtDistance(target: number) {
  let low = 1;
  let high = distances.length - 1;
  while (low < high) {
    const mid = (low + high) >> 1;
    if (distances[mid] < target) low = mid + 1;
    else high = mid;
  }
  return low;
}

// Distance-based travel follows the actual track, independent of OSM node density.
export function journey(progress: number) {
  const clamped = Math.max(0, Math.min(1, progress));
  const target = clamped * totalDistance;
  const index = segmentAtDistance(target);
  const start = route[index - 1];
  const finish = route[index];
  const length = distances[index] - distances[index - 1];
  const ratio = length ? (target - distances[index - 1]) / length : 0;
  const point = [
    start[0] + (finish[0] - start[0]) * ratio,
    start[1] + (finish[1] - start[1]) * ratio,
  ];
  const fromCoord = mapData.route[index - 1];
  const toCoord = mapData.route[index];
  const coordinate = [
    fromCoord[0] + (toCoord[0] - fromCoord[0]) * ratio,
    fromCoord[1] + (toCoord[1] - fromCoord[1]) * ratio,
  ];
  return {
    point,
    coordinate,
    routeIndex: index,
    distance: target,
    get trail() {
      return path([...route.slice(0, index), point]);
    },
  };
}

// Continuous clockwise loop without intermediate station stops.
export const fps = 30;
export const leadIn = 60;
export const rideFrames = 1380;
export const loopEnd = leadIn + rideFrames;
export const durationInFrames = loopEnd + 60;

export function journeyFrame(frame: number) {
  if (frame <= leadIn) {
    return {
      ...journey(0),
      progress: 0,
      legProgress: 0,
      stationIndex: 0,
      nextIndex: 1,
      stopped: true,
      complete: false,
      stopsVisited: 1,
    };
  }
  if (frame >= loopEnd) {
    return {
      ...journey(1),
      progress: 1,
      legProgress: 1,
      stationIndex: 0,
      nextIndex: 1,
      stopped: true,
      complete: true,
      stopsVisited: stations.length,
    };
  }
  const t = (frame - leadIn) / rideFrames;
  const smooth = t * t * (3 - 2 * t);
  const progress = 0.88 * t + 0.12 * smooth;
  const current = journey(progress);
  let stationIndex = 0;
  for (let i = stationDistances.length - 1; i >= 0; i--) {
    if (stationDistances[i] <= current.distance + 1e-6) {
      stationIndex = i;
      break;
    }
  }
  const nextIndex = (stationIndex + 1) % stations.length;
  const legStart = stationDistances[stationIndex];
  const legEnd = stationDistances[stationIndex + 1] ?? totalDistance;
  const legProgress = legEnd > legStart
    ? Math.max(0, Math.min(1, (current.distance - legStart) / (legEnd - legStart)))
    : 0;
  return {
    ...current,
    progress,
    legProgress,
    stationIndex,
    nextIndex,
    stopped: false,
    complete: false,
    stopsVisited: stationIndex + 1,
  };
}

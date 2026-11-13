import {mapData} from './map-data';

export const project = ([longitude, latitude]: number[]) => {
  const mercator = (lat: number) => Math.log(Math.tan(Math.PI / 4 + lat * Math.PI / 360));
  return [40 + (longitude - 114.15) / 0.047 * 880,
    128 + (mercator(22.291) - mercator(latitude)) / (0.047 * Math.PI / 180) * 880];
};
export const route = mapData.route.map(project);
export const stations = mapData.stations.map(station => ({...station, point: project(station.coordinate)}));
export const distances = route.reduce<number[]>((values, point, index) => {
  values.push(index ? values[index - 1] + Math.hypot(point[0] - route[index - 1][0], point[1] - route[index - 1][1]) : 0);
  return values;
}, []);
export const totalDistance = distances[distances.length - 1];
export const path = (points: number[][]) => points.map(([x, y], index) => `${index ? 'L' : 'M'}${x.toFixed(2)},${y.toFixed(2)}`).join(' ');

// Distance-based travel follows the actual track, independent of OSM node density.
export function journey(progress: number) {
  const target = Math.max(0, Math.min(1, progress)) * totalDistance;
  const end = distances.findIndex(value => value >= target);
  const index = Math.max(1, end < 0 ? route.length - 1 : end);
  const start = route[index - 1], finish = route[index];
  const length = distances[index] - distances[index - 1];
  const ratio = length ? (target - distances[index - 1]) / length : 0;
  const point = start.map((value, axis) => value + (finish[axis] - value) * ratio);
  return {point, trail: path([...route.slice(0, index), point]), distance: target};
}
export const stationDistances = stations.map(station => {
  const index = route.findIndex(point => Math.hypot(point[0] - station.point[0], point[1] - station.point[1]) < 0.01);
  if (index < 0) throw Error(`Station is missing from the track: ${station.name}`);
  return distances[index];
});

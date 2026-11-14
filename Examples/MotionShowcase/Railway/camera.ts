import type {Coordinate} from '@motionswift/map';
import {durationInFrames, journeyFrame, loopEnd} from './route';

export const overviewCenter: Coordinate = [139.735, 35.681];
export const overviewZoom = 13;
export const followZoom = 15;
const ease = (value: number) => {
  const t = Math.max(0, Math.min(1, value));
  return t * t * (3 - 2 * t);
};

// Pure frame-derived camera: backward seeks and loop restarts need no retained state.
export function cameraFrame(frame: number) {
  const state = journeyFrame(frame);
  const follow = ease(frame / 90) * (1 - ease((frame - loopEnd) / (durationInFrames - 1 - loopEnd)));
  const center: Coordinate = [
    overviewCenter[0] + (state.coordinate[0] - overviewCenter[0]) * follow,
    overviewCenter[1] + (state.coordinate[1] - overviewCenter[1]) * follow,
  ];
  return {center, zoom: overviewZoom + (followZoom - overviewZoom) * follow, bearing: 0};
}

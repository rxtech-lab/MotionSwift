import {useLayoutEffect} from 'react';
import {interpolate, Easing} from 'remotion';
import {useThree} from '@react-three/fiber';

export type Vec3 = [number, number, number];
export interface CameraKey {frame: number; position: Vec3; target: Vec3; fov: number; roll?: number}

const ease = Easing.inOut(Easing.cubic);
const lerpKeys = (frame: number, keys: CameraKey[], pick: (key: CameraKey) => number) =>
  interpolate(frame, keys.map(key => key.frame), keys.map(pick), {easing: ease, extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});

/** Keyframed camera: position, look-at target, field of view and roll, eased between keys. */
export const CameraRig = ({frame, keys}: {frame: number; keys: CameraKey[]}) => {
  const camera = useThree(state => state.camera);
  useLayoutEffect(() => {
    const position = [0, 1, 2].map(axis => lerpKeys(frame, keys, key => key.position[axis]));
    const target = [0, 1, 2].map(axis => lerpKeys(frame, keys, key => key.target[axis]));
    const roll = lerpKeys(frame, keys, key => key.roll ?? 0);
    camera.position.set(position[0], position[1], position[2]);
    camera.up.set(Math.sin(roll), Math.cos(roll), 0);
    camera.lookAt(target[0], target[1], target[2]);
    camera.fov = lerpKeys(frame, keys, key => key.fov);
    camera.near = 0.1;
    camera.far = 200;
    camera.updateProjectionMatrix();
  }, [camera, frame, keys]);
  return null;
};

/** Eased value between frame keys, for light intensities, colors and object paths. */
export const track = (frame: number, frames: number[], values: number[]) =>
  interpolate(frame, frames, values, {easing: ease, extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});

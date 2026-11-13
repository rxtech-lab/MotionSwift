import React from 'react';
import {AbsoluteFill, useCurrentFrame, useVideoConfig} from 'remotion';
import {ThreeCanvas} from '@remotion/three';
import {Color, DoubleSide} from 'three';
import {CameraRig, CameraKey, track} from './camera';

const GRID = 34;
const keys: CameraKey[] = [
  {frame: 0, position: [-26, 18, 26], target: [0, 0, 0], fov: 50},
  {frame: 40, position: [-6, 4.5, 14], target: [4, 2, -6], fov: 62, roll: -0.15},
  {frame: 75, position: [12, 3, -4], target: [-8, 1, -10], fov: 70, roll: 0.1},
  {frame: 90, position: [22, 26, -22], target: [0, 0, 0], fov: 40},
];
const hash = (x: number, z: number) => {
  const value = Math.sin(x * 127.1 + z * 311.7) * 43758.5453;
  return value - Math.floor(value);
};

// A 34x34 procedural city (1,156 towers), 40 transparent billboards, moving traffic lights and a flythrough.
export const NeonCity = () => {
  const frame = useCurrentFrame();
  const {width, height} = useVideoConfig();
  const dusk = track(frame, [0, 90], [0, 1]);
  const sky = new Color('#0b1030').lerp(new Color('#ff7a45'), 0.35 * (1 - dusk));
  return <AbsoluteFill>
    <ThreeCanvas width={width} height={height}>
      <CameraRig frame={frame} keys={keys} />
      <color attach="background" args={[sky]} />
      <fogExp2 attach="fog" args={[sky, 0.028]} />
      <hemisphereLight args={['#6d7cff', '#140a1e', 0.5 + 0.6 * (1 - dusk)]} />
      <directionalLight position={[-10, 20, 6]} intensity={2.2 * (1 - dusk) + 0.2} color="#ffd2a8" />
      {Array.from({length: 6}, (_, i) => {
        const t = frame / 30 + i * 1.3;
        return <pointLight key={'car' + i} position={[Math.sin(t) * 14, 0.8, (i - 2.5) * 5]} intensity={18 + 22 * dusk}
          color={new Color().setHSL(i / 6, 1, 0.6)} distance={12} decay={2} />;
      })}
      <group position={[0, -0.01, 0]}>
        {Array.from({length: GRID * GRID}, (_, index) => {
          const gx = index % GRID, gz = Math.floor(index / GRID);
          const x = (gx - GRID / 2) * 1.25, z = (gz - GRID / 2) * 1.25;
          const seed = hash(gx, gz);
          const pulse = Math.max(0, Math.sin(frame / 8 - Math.hypot(x, z) / 3));
          const towerHeight = 0.4 + seed * seed * 7 + pulse * 0.8;
          const lit = seed > 0.82;
          return <mesh key={index} position={[x, towerHeight / 2, z]} scale={[0.9, towerHeight, 0.9]}>
            <boxGeometry />
            {lit ? <meshStandardMaterial color="#202538" emissive={new Color().setHSL(seed * 3 % 1, 0.9, 0.5)}
              emissiveIntensity={0.6 + pulse} roughness={0.4} metalness={0.5} />
              : <meshStandardMaterial color={new Color().setHSL(0.62, 0.15, 0.12 + seed * 0.15)} roughness={0.7}
                metalness={0.2} flatShading={seed < 0.2} />}
          </mesh>;
        })}
      </group>
      {Array.from({length: 40}, (_, i) => <mesh key={'sign' + i}
        position={[(i % 8 - 3.5) * 5, 5 + (i % 3) * 1.5 + Math.sin(frame / 10 + i) * 0.3, (Math.floor(i / 8) - 2) * 6]}
        rotation={[0, frame * 0.02 + i, 0]}>
        <planeGeometry args={[2.2, 1]} />
        <meshBasicMaterial color={new Color().setHSL((i * 0.13) % 1, 1, 0.55)} transparent opacity={0.55} side={DoubleSide} />
      </mesh>)}
      <mesh rotation={[-Math.PI / 2, 0, 0]}>
        <planeGeometry args={[60, 60, 1, 1]} />
        <meshPhongMaterial color="#090b14" shininess={10} />
      </mesh>
    </ThreeCanvas>
  </AbsoluteFill>;
};

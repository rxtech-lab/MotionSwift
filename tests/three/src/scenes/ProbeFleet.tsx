import React from 'react';
import {AbsoluteFill, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {ThreeCanvas} from '@remotion/three';
import {useLoader} from '@react-three/fiber';
import {USDLoader} from 'three/addons/loaders/USDLoader.js';
import {CameraRig, CameraKey, track} from './camera';

const keys: CameraKey[] = [
  {frame: 0, position: [0, 1.5, 9], target: [0, 0.4, 0], fov: 45},
  {frame: 45, position: [5, 3.5, 4], target: [0, 0.8, 0], fov: 35, roll: 0.1},
  {frame: 90, position: [-4, -1, 6], target: [0.5, 0.6, 0], fov: 52},
];

const Fleet = ({frame}: {frame: number}) => {
  const probe = useLoader(USDLoader, staticFile('models/probe.usdz'));
  return <>
    <primitive object={probe} rotation={[0.15, frame * 0.04, Math.sin(frame / 20) * 0.1]} position={[0, Math.sin(frame / 15) * 0.2, 0]} />
    {Array.from({length: 12}, (_, i) => {
      const angle = i / 12 * Math.PI * 2 + frame * 0.015;
      return <primitive key={i} object={probe.clone()} scale={0.35}
        position={[Math.cos(angle) * 4, Math.sin(angle * 2) * 0.8, Math.sin(angle) * 4]} rotation={[angle, -angle, 0.3]} />;
    })}
  </>;
};

// USDZ (binary USDC) model instanced 13 times, keyframed camera and animated three-point lighting.
export const ProbeFleet = () => {
  const frame = useCurrentFrame();
  const {width, height} = useVideoConfig();
  return <AbsoluteFill style={{backgroundColor: '#000000'}}>
    <ThreeCanvas width={width} height={height}>
      <CameraRig frame={frame} keys={keys} />
      <color attach="background" args={['#02040a']} />
      <ambientLight intensity={track(frame, [0, 90], [0.15, 0.5])} />
      <directionalLight position={[4, 5, 6]} intensity={track(frame, [0, 30, 90], [3, 1, 2.5])} color="#fff4e0" />
      <directionalLight position={[-6, 2, -3]} intensity={track(frame, [0, 60], [0.2, 2])} color="#5ab0ff" />
      <pointLight position={[0, -2.5, 2]} intensity={track(frame, [30, 75], [0, 25])} color="#ff5030" />
      <Fleet frame={frame} />
    </ThreeCanvas>
  </AbsoluteFill>;
};

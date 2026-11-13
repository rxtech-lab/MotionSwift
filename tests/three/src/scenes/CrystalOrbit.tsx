import React from 'react';
import {AbsoluteFill, useCurrentFrame, useVideoConfig} from 'remotion';
import {ThreeCanvas} from '@remotion/three';
import {Color, DoubleSide, MathUtils} from 'three';
import {CameraRig, CameraKey, track} from './camera';

const keys: CameraKey[] = [
  {frame: 0, position: [0, 3.5, 13], target: [0, 0.5, 0], fov: 48},
  {frame: 30, position: [9, 5, 8], target: [0, 0, 0], fov: 42, roll: 0.08},
  {frame: 60, position: [6, -1.5, -9], target: [0, 1, 0], fov: 55, roll: -0.12},
  {frame: 90, position: [-11, 7, 2], target: [1, 0, 0], fov: 38},
];
const MATERIALS = ['standard', 'physical', 'phong', 'lambert'] as const;
const SHAPES = 4;
const RING = 96;

// 1 torus knot, 2 rings of 96 animated crystals, 24 glass shards, 6 lights, fog and a keyframed camera.
export const CrystalOrbit = () => {
  const frame = useCurrentFrame();
  const {width, height} = useVideoConfig();
  const sun = track(frame, [0, 45, 90], [0.4, 2.6, 1.1]);
  const warm = new Color().setHSL(0.08 + frame / 600, 0.9, 0.55);
  return <AbsoluteFill style={{backgroundColor: '#05060c'}}>
    <ThreeCanvas width={width} height={height}>
      <CameraRig frame={frame} keys={keys} />
      <color attach="background" args={['#070a16']} />
      <fog attach="fog" args={['#070a16', 9, 30]} />
      <ambientLight intensity={0.25} color="#8090ff" />
      <hemisphereLight args={['#9ec5ff', '#3a1f10', 0.6]} />
      <directionalLight position={[5, 8, 4]} intensity={sun} color="#fff2dd" />
      <pointLight position={[Math.cos(frame / 12) * 5, 2, Math.sin(frame / 12) * 5]} intensity={40} color={warm} distance={18} />
      <pointLight position={[0, -3, 0]} intensity={track(frame, [0, 60, 90], [5, 30, 12])} color="#30d0ff" />
      <spotLight position={[0, 9, 0]} angle={0.5} penumbra={0.4} intensity={track(frame, [20, 70], [0, 120])} color="#ffffff" />
      <mesh rotation={[frame * 0.02, frame * 0.035, 0]} scale={1.3}>
        <torusKnotGeometry args={[1.2, 0.38, 220, 28, 2, 3]} />
        <meshPhysicalMaterial color="#ff6a3d" roughness={0.25} metalness={0.6} emissive="#2a0400" />
      </mesh>
      {[0, 1].map(band => <group key={band} rotation={[band ? 0.5 : -0.3, frame * (band ? -0.012 : 0.009), band ? 0.2 : 0]}>
        {Array.from({length: RING}, (_, i) => {
          const angle = (i / RING) * Math.PI * 2;
          const radius = 4.2 + band * 1.6 + Math.sin(i * 1.7 + frame / 9) * 0.35;
          const kind = MATERIALS[(i + band) % MATERIALS.length];
          const color = new Color().setHSL((i / RING + band * 0.3) % 1, 0.75, 0.55);
          const spin = frame * 0.05 + i;
          const material = kind === 'standard' ? <meshStandardMaterial color={color} roughness={0.35} metalness={0.3} flatShading={i % 3 === 0} />
            : kind === 'physical' ? <meshPhysicalMaterial color={color} roughness={0.15} metalness={0.8} />
            : kind === 'phong' ? <meshPhongMaterial color={color} shininess={80} specular="#ffffff" />
            : <meshLambertMaterial color={color} emissive={i % 8 === 0 ? color : '#000000'} emissiveIntensity={0.4} />;
          const shape = i % SHAPES;
          return <mesh key={i} position={[Math.cos(angle) * radius, Math.sin(i * 0.9 + frame / 15) * 0.6, Math.sin(angle) * radius]}
            rotation={[spin, spin * 0.7, 0]} scale={0.22 + (i % 5) * 0.05}>
            {shape === 0 ? <icosahedronGeometry args={[1, i % 2]} /> : shape === 1 ? <octahedronGeometry args={[1, 0]} />
              : shape === 2 ? <dodecahedronGeometry args={[1, 0]} /> : <boxGeometry args={[1.4, 1.4, 1.4]} />}
            {material}
          </mesh>;
        })}
      </group>)}
      {Array.from({length: 24}, (_, i) => {
        const angle = (i / 24) * Math.PI * 2 + frame * 0.01;
        return <mesh key={'glass' + i} position={[Math.cos(angle) * 2.6, 2.4 + Math.sin(i + frame / 10) * 0.3, Math.sin(angle) * 2.6]}
          rotation={[0, -angle, MathUtils.degToRad(20)]}>
          <planeGeometry args={[0.7, 1.1]} />
          <meshStandardMaterial color="#9fe7ff" transparent opacity={0.35} side={DoubleSide} roughness={0.1} metalness={0.1} />
        </mesh>;
      })}
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, -2.2, 0]}>
        <circleGeometry args={[14, 64]} />
        <meshStandardMaterial color="#1a1f33" roughness={0.9} />
      </mesh>
    </ThreeCanvas>
  </AbsoluteFill>;
};

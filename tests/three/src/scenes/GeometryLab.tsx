import React from 'react';
import {AbsoluteFill, useCurrentFrame, useVideoConfig} from 'remotion';
import {ThreeCanvas} from '@remotion/three';
import {BackSide, DoubleSide} from 'three';

const geometries = [
  <boxGeometry args={[1, 1, 1, 2, 2, 2]} />, <sphereGeometry args={[0.6, 32, 16]} />, <cylinderGeometry args={[0.4, 0.6, 1.1, 24]} />,
  <coneGeometry args={[0.6, 1.1, 24]} />, <torusGeometry args={[0.45, 0.18, 16, 48]} />, <torusKnotGeometry args={[0.4, 0.14, 96, 12]} />,
  <icosahedronGeometry args={[0.6, 1]} />, <octahedronGeometry args={[0.6]} />, <tetrahedronGeometry args={[0.65]} />,
  <dodecahedronGeometry args={[0.6]} />, <ringGeometry args={[0.3, 0.6, 32, 2]} />, <circleGeometry args={[0.6, 6]} />,
];
const materials = (hue: number) => [
  <meshBasicMaterial color={`hsl(${hue}, 70%, 55%)`} />,
  <meshLambertMaterial color={`hsl(${hue}, 70%, 55%)`} />,
  <meshPhongMaterial color={`hsl(${hue}, 70%, 55%)`} shininess={60} />,
  <meshStandardMaterial color={`hsl(${hue}, 70%, 55%)`} roughness={0.3} metalness={0.4} />,
  <meshPhysicalMaterial color={`hsl(${hue}, 70%, 55%)`} roughness={0.5} ior={1.8} side={DoubleSide} />,
  <meshNormalMaterial flatShading />,
];

// Every supported geometry x material pair (72 meshes), double/back sides and flat shading.
export const GeometryLab = () => {
  const frame = useCurrentFrame();
  const {width, height} = useVideoConfig();
  return <AbsoluteFill>
    <ThreeCanvas width={width} height={height} camera={{position: [0, 0, 11], fov: 50}}>
      <color attach="background" args={['#e8ecf2']} />
      <ambientLight intensity={0.6} />
      <directionalLight position={[3, 5, 4]} intensity={2.5} />
      <spotLight position={[-6, 3, 6]} angle={0.6} penumbra={0.5} intensity={60} distance={30} color="#ffd0a0" />
      {geometries.map((geometry, column) => materials(column * 30).map((material, row) =>
        <mesh key={`${column}-${row}`} position={[(column - 5.5) * 1.35, (2.5 - row) * 1.25, 0]}
          rotation={[0.5 + frame * 0.03, frame * 0.05 + column, 0]} scale={0.8}>
          {geometry}
          {material}
        </mesh>))}
      <mesh position={[0, 0, -4]} scale={[12, 7, 1]}>
        <planeGeometry />
        <meshStandardMaterial color="#c8d0dc" side={BackSide} roughness={1} />
      </mesh>
    </ThreeCanvas>
  </AbsoluteFill>;
};

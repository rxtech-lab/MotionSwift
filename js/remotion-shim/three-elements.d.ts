// React Three Fiber intrinsic elements supported inside <ThreeCanvas>.
import type {Key, ReactNode} from 'react';
import type {Color, Euler, Vector3, Quaternion, Group, Side, EulerOrder} from './three';
type Vec3 = Vector3 | [number, number, number];
type ColorProp = Color | string | number | [number, number, number];
interface Base { key?: Key | null; children?: ReactNode; name?: string; 'data-ms-src'?: string }
export interface Object3DProps extends Base {
  position?: Vec3 | number; rotation?: Euler | [number, number, number] | [number, number, number, EulerOrder];
  scale?: Vec3 | number; quaternion?: Quaternion | [number, number, number, number];
  'position-x'?: number; 'position-y'?: number; 'position-z'?: number;
  'rotation-x'?: number; 'rotation-y'?: number; 'rotation-z'?: number;
  'scale-x'?: number; 'scale-y'?: number; 'scale-z'?: number;
  visible?: boolean; renderOrder?: number; castShadow?: boolean; receiveShadow?: boolean; frustumCulled?: boolean;
}
interface GeometryProps<A extends unknown[]> extends Base { args?: A; attach?: string }
export interface MaterialProps extends Base {
  attach?: string; color?: ColorProp; emissive?: ColorProp; emissiveIntensity?: number; roughness?: number; metalness?: number;
  opacity?: number; transparent?: boolean; side?: Side; flatShading?: boolean; specular?: ColorProp; shininess?: number;
  toneMapped?: boolean; depthTest?: boolean; depthWrite?: boolean; fog?: boolean; ior?: number; visible?: boolean;
  wireframe?: false; vertexColors?: false;
}
export interface LightProps extends Object3DProps { color?: ColorProp; intensity?: number; args?: unknown[] }
export interface ThreeElements {
  group: Object3DProps; object3D: Object3DProps; mesh: Object3DProps;
  primitive: Object3DProps & {object: Group};
  ambientLight: LightProps; directionalLight: LightProps;
  pointLight: LightProps & {distance?: number; decay?: number};
  spotLight: LightProps & {distance?: number; decay?: number; angle?: number; penumbra?: number};
  hemisphereLight: LightProps & {groundColor?: ColorProp};
  color: Base & {attach: 'background'; args: [ColorProp]};
  fog: Base & {attach: 'fog'; args: [ColorProp, number?, number?]};
  fogExp2: Base & {attach: 'fog'; args: [ColorProp, number?]};
  boxGeometry: GeometryProps<[number?, number?, number?, number?, number?, number?]>;
  sphereGeometry: GeometryProps<[number?, number?, number?, number?, number?, number?, number?]>;
  planeGeometry: GeometryProps<[number?, number?, number?, number?]>;
  cylinderGeometry: GeometryProps<[number?, number?, number?, number?, number?, boolean?, number?, number?]>;
  coneGeometry: GeometryProps<[number?, number?, number?, number?, boolean?, number?, number?]>;
  torusGeometry: GeometryProps<[number?, number?, number?, number?, number?]>;
  torusKnotGeometry: GeometryProps<[number?, number?, number?, number?, number?, number?]>;
  circleGeometry: GeometryProps<[number?, number?, number?, number?]>;
  ringGeometry: GeometryProps<[number?, number?, number?, number?, number?, number?]>;
  icosahedronGeometry: GeometryProps<[number?, number?]>; octahedronGeometry: GeometryProps<[number?, number?]>;
  tetrahedronGeometry: GeometryProps<[number?, number?]>; dodecahedronGeometry: GeometryProps<[number?, number?]>;
  meshBasicMaterial: MaterialProps; meshLambertMaterial: MaterialProps; meshPhongMaterial: MaterialProps;
  meshStandardMaterial: MaterialProps; meshPhysicalMaterial: MaterialProps; meshNormalMaterial: MaterialProps;
}

// The `three` subset available in MotionSwift compositions: math, colors and side constants.
export type ColorRepresentation = Color | string | number;
export declare const MathUtils: {
  DEG2RAD: number; RAD2DEG: number; degToRad(degrees: number): number; radToDeg(radians: number): number;
  clamp(value: number, min: number, max: number): number; lerp(x: number, y: number, t: number): number;
  inverseLerp(x: number, y: number, value: number): number; mapLinear(x: number, a1: number, a2: number, b1: number, b2: number): number;
  euclideanModulo(n: number, m: number): number; smoothstep(x: number, min: number, max: number): number;
  smootherstep(x: number, min: number, max: number): number; pingpong(x: number, length?: number): number;
};
export declare class Vector2 { constructor(x?: number, y?: number); x: number; y: number; set(x: number, y: number): this; toArray(): [number, number]; }
export declare class Vector3 {
  constructor(x?: number, y?: number, z?: number); x: number; y: number; z: number; readonly isVector3: true;
  set(x: number, y: number, z?: number): this; setScalar(s: number): this; setX(x: number): this; setY(y: number): this; setZ(z: number): this;
  copy(v: Vector3): this; clone(): Vector3; add(v: Vector3): this; addScalar(s: number): this; addVectors(a: Vector3, b: Vector3): this;
  addScaledVector(v: Vector3, s: number): this; sub(v: Vector3): this; subVectors(a: Vector3, b: Vector3): this;
  multiplyScalar(s: number): this; divideScalar(s: number): this; negate(): this; dot(v: Vector3): number;
  lengthSq(): number; length(): number; normalize(): this; setLength(l: number): this; distanceTo(v: Vector3): number;
  lerp(v: Vector3, a: number): this; lerpVectors(a: Vector3, b: Vector3, t: number): this; cross(v: Vector3): this;
  crossVectors(a: Vector3, b: Vector3): this; applyQuaternion(q: Quaternion): this; applyEuler(e: Euler): this;
  setFromSphericalCoords(radius: number, phi: number, theta: number): this; setFromCylindricalCoords(radius: number, theta: number, y: number): this;
  equals(v: Vector3): boolean; fromArray(array: ArrayLike<number>, offset?: number): this; toArray(): [number, number, number];
}
export type EulerOrder = 'XYZ' | 'YXZ' | 'ZXY' | 'ZYX' | 'YZX' | 'XZY';
export declare class Euler {
  constructor(x?: number, y?: number, z?: number, order?: EulerOrder); x: number; y: number; z: number; order: EulerOrder;
  set(x: number, y: number, z: number, order?: EulerOrder): this; copy(e: Euler): this; clone(): Euler; toArray(): [number, number, number, EulerOrder];
}
export declare class Quaternion {
  constructor(x?: number, y?: number, z?: number, w?: number); x: number; y: number; z: number; w: number;
  set(x: number, y: number, z: number, w: number): this; copy(q: Quaternion): this; clone(): Quaternion; identity(): this;
  setFromEuler(e: Euler): this; setFromAxisAngle(axis: Vector3, angle: number): this; multiply(q: Quaternion): this;
  premultiply(q: Quaternion): this; multiplyQuaternions(a: Quaternion, b: Quaternion): this; toArray(): [number, number, number, number];
}
export declare class Color {
  constructor(color?: ColorRepresentation); constructor(r: number, g: number, b: number); r: number; g: number; b: number; readonly isColor: true;
  set(color: ColorRepresentation): this; set(r: number, g: number, b: number): this; setScalar(s: number): this; setHex(hex: number): this;
  setRGB(r: number, g: number, b: number, colorSpace?: string): this; setHSL(h: number, s: number, l: number, colorSpace?: string): this;
  setStyle(style: string): this; copy(c: Color): this; clone(): Color; multiplyScalar(s: number): this; lerp(c: Color, a: number): this;
  lerpColors(a: Color, b: Color, t: number): this; getHex(): number; getHexString(): string; getStyle(): string; toArray(): [number, number, number];
}
export declare class Object3D {
  position: Vector3; rotation: Euler; quaternion: Quaternion; scale: Vector3; up: Vector3;
  lookAt(target: Vector3): void; lookAt(x: number, y: number, z: number): void; updateMatrix(): void; updateMatrixWorld(): void;
}
export declare class PerspectiveCamera extends Object3D {
  constructor(fov?: number, aspect?: number, near?: number, far?: number);
  fov: number; aspect: number; near: number; far: number; zoom: number; readonly isCamera: true; readonly isPerspectiveCamera: true;
  updateProjectionMatrix(): void;
}
export type Group = Object3D & {readonly isGroup: true; clone(): Group};
export type Side = 0 | 1 | 2;
export declare const FrontSide: 0; export declare const BackSide: 1; export declare const DoubleSide: 2;
export declare const NoToneMapping: 0; export declare const ACESFilmicToneMapping: 4;
export declare const SRGBColorSpace: 'srgb'; export declare const LinearSRGBColorSpace: 'srgb-linear'; export declare const NoColorSpace: '';

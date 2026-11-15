import type {ReactNode, ReactElement} from 'react';
import type {PerspectiveCamera, Group} from './three';
import type {USDLoader} from './usd-loader';
import type {MotionCSSProperties} from './index';
export interface RootState {
  camera: PerspectiveCamera; size: {width: number; height: number; top: number; left: number};
  viewport: {width: number; height: number; aspect: number; dpr: number; factor: number; distance: number};
  scene: {readonly isScene: true}; flat: boolean; dpr: [number, number];
  set(partial: Partial<RootState> | ((state: RootState) => Partial<RootState>)): void; get(): RootState;
  invalidate(): void; advance(timestamp?: number): void;
}
export declare function useThree(): RootState;
export declare function useThree<T>(selector: (state: RootState) => T): T;
/** Not supported: animate from useCurrentFrame() instead. */
export declare function useFrame(callback: (...args: unknown[]) => void): never;
export declare function useLoader(loader: typeof USDLoader, url: string): Group;
export declare function useLoader(loader: typeof USDLoader, url: string[]): Group[];
export interface CameraOptions {
  fov?: number; near?: number; far?: number; zoom?: number; aspect?: number;
  position?: [number, number, number]; rotation?: [number, number, number]; up?: [number, number, number];
  quaternion?: [number, number, number, number];
}
export interface ThreeCanvasProps {
  width: number; height: number; style?: MotionCSSProperties; children?: ReactNode;
  camera?: CameraOptions | PerspectiveCamera; flat?: boolean; dpr?: number | [number, number];
  onCreated?: (state: RootState) => void; frameloop?: 'always' | 'demand' | 'never';
}
export declare function ThreeCanvas(props: ThreeCanvasProps): ReactElement;

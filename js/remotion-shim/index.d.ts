import type {ComponentType, ReactNode, ReactElement, Key} from 'react';

export interface MotionCSSProperties {
  display?: 'flex' | 'none';
  position?: 'relative' | 'absolute';
  flexDirection?: 'row' | 'column' | 'row-reverse' | 'column-reverse';
  flexWrap?: 'wrap' | 'nowrap';
  justifyContent?: 'flex-start' | 'center' | 'flex-end' | 'space-between' | 'space-around' | 'space-evenly';
  alignItems?: 'flex-start' | 'center' | 'flex-end' | 'stretch';
  alignSelf?: MotionCSSProperties['alignItems'];
  width?: number | string; height?: number | string;
  minWidth?: number | string; maxWidth?: number | string; minHeight?: number | string; maxHeight?: number | string;
  left?: number | string; right?: number | string; top?: number | string; bottom?: number | string; inset?: number | string;
  margin?: number | string; marginLeft?: number | string; marginRight?: number | string; marginTop?: number | string; marginBottom?: number | string;
  padding?: number | string; paddingLeft?: number | string; paddingRight?: number | string; paddingTop?: number | string; paddingBottom?: number | string;
  gap?: number | string; rowGap?: number | string; columnGap?: number | string;
  flexGrow?: number; flexShrink?: number; flexBasis?: number | string; aspectRatio?: number;
  backgroundColor?: string; background?: string; color?: string;
  opacity?: number; borderRadius?: number | string; overflow?: 'hidden' | 'visible';
  transform?: string; transformOrigin?: 'center'; fontSize?: number; fontFamily?: string;
  objectFit?: 'contain';
}
export interface BoxProps {key?: Key | null; style?: MotionCSSProperties; children?: ReactNode; id?: string; 'data-ms-src'?: string}
export declare const AbsoluteFill: ComponentType<BoxProps>;
export declare const Folder: ComponentType<{children?: ReactNode; name?: string}>;
export declare function registerRoot(root: ComponentType): void;
export interface VideoConfig {id: string; width: number; height: number; fps: number; durationInFrames: number}
export declare function useCurrentFrame(): number;
export declare function useVideoConfig(): VideoConfig;
export declare const Composition: ComponentType<VideoConfig & {component: ComponentType<any>; defaultProps?: Record<string,unknown>}>;
export declare const Still: ComponentType<Omit<VideoConfig,'fps'|'durationInFrames'> & {component: ComponentType<any>; defaultProps?: Record<string,unknown>}>;
export declare function interpolate(value: number,input: number[],output: number[],options?: {
  extrapolateLeft?: 'extend'|'clamp'|'identity'|'wrap'; extrapolateRight?: 'extend'|'clamp'|'identity'|'wrap'; easing?: (x:number)=>number
}): number;
export declare function spring(options: {frame:number;fps:number;from?:number;to?:number;config?: {
  mass?:number;stiffness?:number;damping?:number;overshootClamping?:boolean
}}): number;
export declare const Sequence: ComponentType<{from?:number;durationInFrames?:number;children?:ReactNode;layout?:'none'|'absolute-fill';style?:MotionCSSProperties}>;
export declare const Freeze: ComponentType<{frame:number;children?:ReactNode}>;
export declare const Loop: ComponentType<{durationInFrames:number;times?:number;children?:ReactNode}>;
export declare const Easing: {
  linear:(x:number)=>number;quad:(x:number)=>number;cubic:(x:number)=>number;sin:(x:number)=>number;exp:(x:number)=>number;circle:(x:number)=>number;
  in:(easing:(x:number)=>number)=>(x:number)=>number;out:(easing:(x:number)=>number)=>(x:number)=>number;inOut:(easing:(x:number)=>number)=>(x:number)=>number;
};

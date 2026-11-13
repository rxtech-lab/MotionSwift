import type {ComponentType, ReactNode, ReactElement, Key} from 'react';

export interface MotionCSSProperties {
  display?: 'flex' | 'inline-flex' | 'inline' | 'inline-block' | 'none';
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
  flex?: number | string; zIndex?: number | 'auto'; boxSizing?: 'border-box' | 'content-box';
  pointerEvents?: 'auto' | 'none'; userSelect?: 'auto' | 'none' | 'text' | 'all'; cursor?: string;
  border?: string; borderTop?: string; borderRight?: string; borderBottom?: string; borderLeft?: string;
  borderWidth?: number | string; borderColor?: string; borderStyle?: 'solid' | 'none' | 'hidden';
  borderTopWidth?: number | string; borderRightWidth?: number | string; borderBottomWidth?: number | string; borderLeftWidth?: number | string;
  borderTopColor?: string; borderRightColor?: string; borderBottomColor?: string; borderLeftColor?: string;
  borderTopStyle?: 'solid' | 'none' | 'hidden'; borderRightStyle?: 'solid' | 'none' | 'hidden'; borderBottomStyle?: 'solid' | 'none' | 'hidden'; borderLeftStyle?: 'solid' | 'none' | 'hidden';
  flexGrow?: number; flexShrink?: number; flexBasis?: number | string; aspectRatio?: number;
  /** Effects accept only the grammar documented in docs/compatibility.md; runtime validates values. */
  backgroundImage?: string; boxShadow?: string; filter?: string; backdropFilter?: string;
  mixBlendMode?: 'normal' | 'multiply' | 'screen' | 'overlay' | 'darken' | 'lighten' | 'color-dodge' | 'color-burn' | 'hard-light' | 'soft-light' | 'difference' | 'exclusion' | 'hue' | 'saturation' | 'color' | 'luminosity';
  clipPath?: string; maskImage?: string;
  backgroundColor?: string; background?: string; color?: string;
  opacity?: number; borderRadius?: number | string; overflow?: 'hidden' | 'visible';
  transform?: string; transformOrigin?: string; fontSize?: number; fontFamily?: string; fontWeight?: number | string; fontStyle?: "normal" | "italic"; lineHeight?: number | string; letterSpacing?: number; textAlign?: "left" | "center" | "right" | "start" | "end" | "justify"; whiteSpace?: "normal" | "pre" | "pre-wrap"; textTransform?: "none" | "uppercase" | "lowercase";
  objectFit?: 'contain' | 'cover' | 'fill';
}
export interface MotionKeyframe {frame: number; value: number; easing: 'linear' | 'hold'}
export interface MotionObjectTiming {
  from: number; duration: number | null; keyframes: Record<string, MotionKeyframe[]>;
}
export interface BoxProps {
  /** Optional inspector labels/groups for CSS properties authored in style. Does not affect rendering. */
  'data-ms-properties'?: Record<string, {label?: string; group?: string}>;
  key?: Key | null; style?: MotionCSSProperties; children?: ReactNode; id?: string;
  'data-ms-src'?: string; 'data-ms-timeline'?: MotionObjectTiming;
}
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
export interface SpringConfig {mass:number;stiffness:number;damping:number;overshootClamping:boolean}
export interface SpringOptions {frame:number;fps:number;from?:number;to?:number;config?:Partial<SpringConfig>;durationInFrames?:number;durationRestThreshold?:number;delay?:number;reverse?:boolean}
export declare function spring(options: SpringOptions): number;
export declare function measureSpring(options: {fps:number;config?:Partial<SpringConfig>;threshold?:number;from?:number;to?:number}): number;
export declare function random(seed: string | number): number;
export declare const Sequence: ComponentType<{from?:number;durationInFrames?:number;children?:ReactNode;layout?:'none'|'absolute-fill';style?:MotionCSSProperties}>;
export declare const Series: ComponentType<React.ComponentProps<typeof Sequence>> & {
  Sequence: ComponentType<Omit<React.ComponentProps<typeof Sequence>, 'from' | 'durationInFrames'> & {durationInFrames:number;offset?:number}>;
};
export declare const Freeze: ComponentType<{frame:number;children?:ReactNode}>;
export declare const Loop: ComponentType<{durationInFrames:number;times?:number;children?:ReactNode}>;
export declare const Easing: {
  bezier:(x1:number,y1:number,x2:number,y2:number)=>(x:number)=>number;
  ease:(x:number)=>number;step0:(x:number)=>number;step1:(x:number)=>number;bounce:(x:number)=>number;
  poly:(n:number)=>(x:number)=>number;back:(s?:number)=>(x:number)=>number;elastic:(b?:number)=>(x:number)=>number;
  linear:(x:number)=>number;quad:(x:number)=>number;cubic:(x:number)=>number;sin:(x:number)=>number;exp:(x:number)=>number;circle:(x:number)=>number;
  in:(easing:(x:number)=>number)=>(x:number)=>number;out:(easing:(x:number)=>number)=>(x:number)=>number;inOut:(easing:(x:number)=>number)=>(x:number)=>number;
};

export declare function delayRender(label?: string, options?: {timeoutInMilliseconds?: number}): number;
export declare function continueRender(handle: number): void;
export declare function cancelRender(error: Error | string): void;

export interface MediaProps extends BoxProps {
  src: string; trimBefore?: number; trimAfter?: number; startFrom?: number; endAt?: number;
  durationInFrames?: number; playbackRate?: number; volume?: number | ((frame: number) => number); muted?: boolean;
}
export declare const Audio: ComponentType<MediaProps>;
export declare const OffthreadVideo: ComponentType<MediaProps>;
export declare const Video: typeof OffthreadVideo;
export declare const Img: ComponentType<BoxProps & {src: string}>;

/** A file in the project's public/ folder, for example a USDZ model or an image. */
export declare function staticFile(path: string): string;

export declare function interpolateColors(value:number,input:number[],output:string[]): string;
export interface RemotionEnvironment {isRendering:boolean;isStudio:boolean;isPlayer:boolean;isClientSideRendering:boolean}
export declare function getRemotionEnvironment(): RemotionEnvironment;
export declare function useRemotionEnvironment(): RemotionEnvironment;

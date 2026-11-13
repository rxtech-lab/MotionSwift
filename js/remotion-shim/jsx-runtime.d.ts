import type * as React from 'react';
import type {BoxProps} from './index';
import type {ThreeElements} from './three-elements';
export declare function jsx(type: any,props: any,key?: React.Key): React.ReactElement;
export declare const jsxs: typeof jsx;
export declare const Fragment: typeof React.Fragment;
export namespace JSX {
  type Element = React.ReactElement;
  type ElementType = keyof IntrinsicElements | React.JSXElementConstructor<any>;
  interface ElementChildrenAttribute {children: {}}
  interface IntrinsicAttributes {key?: React.Key | null}
  // Inline SVG is an atomic vector island; descendants have no Yoga/editor boxes.
  interface IntrinsicElements extends ThreeElements {
    div: BoxProps; span: BoxProps;
    img: BoxProps & {src: string};
    /** XML construction only (for existing data-URI serializers); rejected as inline hosts. */
    text: React.SVGProps<SVGTextElement>; pattern: React.SVGProps<SVGPatternElement>;
    svg: SVGHostProps; g: SVGHostProps; defs: SVGHostProps; path: SVGHostProps;
    rect: SVGHostProps; circle: SVGHostProps; ellipse: SVGHostProps; line: SVGHostProps;
    polyline: SVGHostProps; polygon: SVGHostProps; clipPath: SVGHostProps; mask: SVGHostProps;
    radialGradient: SVGHostProps; linearGradient: SVGHostProps; stop: SVGHostProps;
  }
}
/** Supported SVG attributes only. Style on the root is MotionCSSProperties; use
 * presentation attributes for descendants. Values are strictly checked at runtime. */
export interface SVGHostProps {
  children?: React.ReactNode; key?: React.Key | null; style?: import('./index').MotionCSSProperties;
  id?: string; viewBox?: string; preserveAspectRatio?: string;
  width?: number | string; height?: number | string; x?: number | string; y?: number | string;
  x1?: number | string; y1?: number | string; x2?: number | string; y2?: number | string;
  cx?: number | string; cy?: number | string; r?: number | string; rx?: number | string; ry?: number | string;
  fx?: number | string; fy?: number | string; fr?: number | string;
  d?: string; points?: string; fill?: string; fillRule?: 'nonzero' | 'evenodd'; fillOpacity?: number;
  stroke?: string; strokeWidth?: number | string; strokeOpacity?: number;
  strokeLinecap?: 'butt' | 'round' | 'square'; strokeLinejoin?: 'miter' | 'round' | 'bevel';
  strokeMiterlimit?: number; strokeDasharray?: string; strokeDashoffset?: number | string;
  opacity?: number; transform?: string; clipPath?: string; clipRule?: 'nonzero' | 'evenodd';
  clipPathUnits?: 'userSpaceOnUse' | 'objectBoundingBox'; mask?: string;
  maskUnits?: 'userSpaceOnUse' | 'objectBoundingBox'; maskContentUnits?: 'userSpaceOnUse' | 'objectBoundingBox';
  gradientUnits?: 'userSpaceOnUse' | 'objectBoundingBox'; gradientTransform?: string;
  spreadMethod?: 'pad' | 'reflect' | 'repeat'; offset?: number | string; stopColor?: string; stopOpacity?: number;
}

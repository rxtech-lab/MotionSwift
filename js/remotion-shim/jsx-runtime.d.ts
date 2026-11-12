import type * as React from 'react';
import type {BoxProps} from './index';
export declare function jsx(type: any,props: any,key?: React.Key): React.ReactElement;
export declare const jsxs: typeof jsx;
export declare const Fragment: typeof React.Fragment;
export namespace JSX {
  type Element = React.ReactElement;
  type ElementType = keyof IntrinsicElements | React.JSXElementConstructor<any>;
  interface ElementChildrenAttribute {children: {}}
  interface IntrinsicAttributes {key?: React.Key | null}
  // SVG elements can be used as XML construction values. Direct host SVG is
  // rejected by the painter; the supported render path is an SVG data-URI img.
  interface IntrinsicElements {
    div: BoxProps; span: BoxProps;
    img: BoxProps & {src: string};
    svg: React.SVGProps<SVGSVGElement>; g: React.SVGProps<SVGGElement>;
    defs: React.SVGProps<SVGDefsElement>; path: React.SVGProps<SVGPathElement>;
    rect: React.SVGProps<SVGRectElement>; circle: React.SVGProps<SVGCircleElement>;
    ellipse: React.SVGProps<SVGEllipseElement>; text: React.SVGProps<SVGTextElement>;
    radialGradient: React.SVGProps<SVGRadialGradientElement>;
    linearGradient: React.SVGProps<SVGLinearGradientElement>;
    stop: React.SVGProps<SVGStopElement>; pattern: React.SVGProps<SVGPatternElement>;
  }
}

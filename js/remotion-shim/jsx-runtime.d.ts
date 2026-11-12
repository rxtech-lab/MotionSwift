import type * as React from 'react';
import type {BoxProps} from './index';
export declare function jsx(type: any,props: any,key?: React.Key): React.ReactElement;
export declare const jsxs: typeof jsx;
export declare const Fragment: typeof React.Fragment;
export namespace JSX {
  type Element = React.ReactElement;
  type ElementType = 'div' | 'span' | React.JSXElementConstructor<any>;
  interface ElementChildrenAttribute {children: {}}
  interface IntrinsicAttributes {key?: React.Key | null}
  interface IntrinsicElements {div: BoxProps; span: BoxProps}
}

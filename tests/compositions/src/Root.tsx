import React from 'react';
import {Composition} from 'remotion';
import {Solid, Boxes, Motion, Flex, Layers, Timed} from '../visuals/Boxes';

import {BorderOrder, FlexOrigin, SeriesTiming, NestedOrder} from '../visuals/CoreContracts';

import {Gradients, Shadows, Filters, Blending, ClipMask, Backdrop, Transform3D, InlineSVG, ExternalSVG, FadeTransition, SlideTransition, WipeTransition} from '../visuals/Effects';

export const Root = () => <>
  {[Solid, Boxes, Motion, Flex, Layers, Timed, BorderOrder, FlexOrigin, SeriesTiming, NestedOrder, Gradients, Shadows, Filters, Blending, ClipMask, Backdrop, Transform3D, InlineSVG, ExternalSVG, FadeTransition, SlideTransition, WipeTransition].map(component => <Composition key={component.name}
    id={component.name} component={component} width={320} height={180} fps={30} durationInFrames={30} />)}
</>;

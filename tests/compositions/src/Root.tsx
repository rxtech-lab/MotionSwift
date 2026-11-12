import React from 'react';
import {Composition} from 'remotion';
import {Solid, Boxes, Motion, Flex, Layers, Timed} from '../visuals/Boxes';

export const Root = () => <>
  {[Solid, Boxes, Motion, Flex, Layers, Timed].map(component => <Composition key={component.name}
    id={component.name} component={component} width={320} height={180} fps={30} durationInFrames={30} />)}
</>;

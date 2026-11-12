import React from 'react';
import {Composition, Loop, registerRoot} from 'remotion';
import {Flex, Layers, Timed} from '../compositions/visuals/Boxes';

// Separate entry keeps the visual golden compositions and their duration unchanged.
const LoopingTimed = () => <Loop durationInFrames={30}><Timed /></Loop>;
const BenchmarkRoot = () => <>
  {[Flex, Layers, LoopingTimed].map(component => <Composition key={component.name}
    id={component.name} component={component} width={320} height={180} fps={30} durationInFrames={300} />)}
</>;
registerRoot(BenchmarkRoot);

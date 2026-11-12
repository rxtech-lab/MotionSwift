import React from 'react';
import {AbsoluteFill, Composition, registerRoot} from 'remotion';
enum Tone { Background = '#14213d' }
namespace Dimensions { export const width = 320; }
const values = {color: Tone.Background} satisfies {color: string};
const Scene = () => <AbsoluteFill style={{backgroundColor: values.color}} />;
const Root = () => <Composition id="Types" component={Scene} width={Dimensions.width} height={180} fps={30} durationInFrames={30} />;
registerRoot(Root);

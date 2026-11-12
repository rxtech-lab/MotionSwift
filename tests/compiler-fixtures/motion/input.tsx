import React from 'react';
import {AbsoluteFill, Composition, registerRoot, spring, useCurrentFrame} from 'remotion';
const Scene = () => {
  const frame = useCurrentFrame();
  return <AbsoluteFill>{[10,30].flatMap(fps => [5,10,35].map(damping =>
    <div key={`${fps}-${damping}`} style={{left: spring({frame,fps,config:{damping}})}} />))}</AbsoluteFill>;
};
registerRoot(() => <Composition id="Math" component={Scene} width={320} height={180} fps={30} durationInFrames={30} />);

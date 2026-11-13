import React from 'react';
import {AbsoluteFill, Composition, registerRoot, spring, Easing, random, measureSpring, useCurrentFrame} from 'remotion';
const Scene = () => {
  const frame = useCurrentFrame();
  return <AbsoluteFill>{[10,30].flatMap(fps => [5,10,35].map(damping =>
    <div key={`${fps}-${damping}`} style={{left: spring({frame,fps,config:{damping}})}} />))}
    {[spring({frame,fps:30,durationInFrames:12,delay:3,reverse:true}),
      spring({frame:frame+0.25,fps:10,durationInFrames:18,config:{damping:35},from:3,to:-2}),
      measureSpring({fps:30,config:{damping:5},threshold:0.001}),
      Easing.bezier(0.16,1,0.3,1)(frame/29), Easing.back(2)(frame/29), Easing.ease(frame/29),
      random('hello'), random(frame)].map((left,index)=><div key={index} style={{left}} />)}</AbsoluteFill>;
};
registerRoot(() => <Composition id="Math" component={Scene} width={320} height={180} fps={30} durationInFrames={30} />);

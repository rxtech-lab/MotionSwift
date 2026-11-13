import React from 'react';
import {AbsoluteFill, Series, Sequence, Easing, spring, measureSpring, random, interpolateColors, type SpringConfig} from 'remotion';
const config: Partial<SpringConfig> = {mass:1,stiffness:100,damping:12,overshootClamping:true};
export const Contracts = () => <AbsoluteFill style={{display:'inline-flex', flex:'1 0 20%', boxSizing:'border-box', pointerEvents:'none', userSelect:'none', cursor:'default', border:'3px solid red', borderTop:'0 solid transparent', borderColor:'rgba(0,0,0,0.5)', zIndex:2, transformOrigin:'left bottom'}}>
  <Series from={2}>
    <Series.Sequence durationInFrames={20} offset={-2}><Sequence from={3} layout="none">
      <div style={{left:spring({frame:12,fps:30,config,delay:4,reverse:true,durationInFrames:20,durationRestThreshold:0.001}), top:measureSpring({fps:30,config}), opacity:Easing.ease(0.5), backgroundColor:interpolateColors(random('color'),[0,1],['red','blue'])}} />
    </Sequence></Series.Sequence>
    <Series.Sequence durationInFrames={12} offset={2} />
  </Series>
</AbsoluteFill>;

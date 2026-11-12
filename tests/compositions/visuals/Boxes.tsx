import React from 'react';
import {AbsoluteFill, interpolate, Sequence, spring, useCurrentFrame, useVideoConfig} from 'remotion';

export const Solid = () => <AbsoluteFill style={{backgroundColor: '#14213d'}} />;
export const Boxes = () => <AbsoluteFill style={{backgroundColor: '#14213d'}}>
  <div style={{position: 'absolute', left: 24, top: 20, width: 110, height: 80, backgroundColor: '#fca311'}} />
  <div style={{position: 'absolute', right: 24, bottom: 20, width: 110, height: 80, borderRadius: 16, backgroundColor: '#e5e5e5'}} />
</AbsoluteFill>;
export const Motion = () => {
  const frame = useCurrentFrame();
  const x = interpolate(frame, [0, 29], [0, 220], {extrapolateRight: 'clamp'});
  return <AbsoluteFill style={{backgroundColor: '#14213d'}}>
    <div style={{position: 'absolute', left: 16, top: 50, width: 60, height: 60,
      backgroundColor: '#fca311', transform: `translateX(${x}px)`}} />
  </AbsoluteFill>;
};
export const Flex = () => <AbsoluteFill style={{backgroundColor: '#14213d', justifyContent: 'center', alignItems: 'center'}}>
  <div style={{display: 'flex', flexDirection: 'row', width: 240, height: 60, gap: 12}}>
    {['#fca311', '#e5e5e5', '#ff0000'].map(color => <div key={color} style={{width: 72, height: 60, backgroundColor: color}} />)}
  </div>
</AbsoluteFill>;
export const Layers = () => <AbsoluteFill style={{backgroundColor: '#14213d'}}>
  <div style={{position: 'absolute', left: 50, top: 40, width: 100, height: 100, backgroundColor: '#fca311'}} />
  <div style={{position: 'absolute', left: 100, top: 60, width: 100, height: 100, opacity: 0.5, backgroundColor: '#e5e5e5'}} />
</AbsoluteFill>;
export const Timed = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const scale = spring({frame, fps});
  return <AbsoluteFill style={{backgroundColor: '#14213d'}}>
    <Sequence from={10} durationInFrames={15}>
      <div style={{position: 'absolute', left: 100, top: 40, width: 100, height: 100,
        backgroundColor: '#fca311', transform: `scale(${scale})`}} />
    </Sequence>
  </AbsoluteFill>;
};

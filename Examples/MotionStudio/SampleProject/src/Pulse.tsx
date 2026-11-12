import React from 'react';
import {AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';

// Animated values are classified as animated: canvas gestures explain why they are refused.
export const Pulse = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const size = interpolate(spring({frame, fps}), [0, 1], [40, 200]);
  return <AbsoluteFill style={{backgroundColor: '#1d3557', justifyContent: 'center', alignItems: 'center'}}>
    <div style={{width: size, height: size, borderRadius: 32, backgroundColor: '#e63946'}} />
    <div style={{position: 'absolute', left: 32, top: interpolate(frame, [0, 89], [32, 280]), width: 48, height: 48, backgroundColor: '#f1faee'}} />
  </AbsoluteFill>;
};

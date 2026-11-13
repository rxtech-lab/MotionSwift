import React from 'react';
import {AbsoluteFill, Composition, Img, registerRoot, staticFile, useCurrentFrame} from 'remotion';
import {journey} from './route';

export const IslandRailway = () => {
  const frame = useCurrentFrame();
  const progress = Math.max(0, Math.min(1, (frame - 24) / 300));
  const {point} = journey(progress);
  return <AbsoluteFill style={{backgroundColor: '#ecebe2', overflow: 'hidden'}}>
    <Img src={staticFile('map.png')} style={{position: 'absolute', width: 960, height: 540}} />
    <div style={{position: 'absolute', left: point[0] - 15, top: point[1] - 15,
      width: 30, height: 30, borderRadius: 15, backgroundColor: '#ff785b', opacity: 0.25}} />
    <div data-ms-properties={{backgroundColor: {label: 'Train color', group: 'Map'}}}
      style={{position: 'absolute', left: point[0] - 8, top: point[1] - 8,
        width: 16, height: 16, borderRadius: 8, backgroundColor: '#ff674c'}} />
    <div style={{position: 'absolute', left: 36, top: 534, width: progress * 880, height: 3,
      backgroundColor: '#ff785b'}} />
  </AbsoluteFill>;
};
registerRoot(() => <Composition id="IslandRailway" component={IslandRailway}
  width={960} height={540} fps={30} durationInFrames={360} />);

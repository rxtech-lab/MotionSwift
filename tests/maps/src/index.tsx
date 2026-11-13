import React from 'react';
import {AbsoluteFill, Composition, Img, registerRoot, staticFile, useCurrentFrame} from 'remotion';

// Synthetic local imagery exercises the provider output formats, not provider services.
const Marker = () => {
  const frame = useCurrentFrame();
  return <div style={{position: 'absolute', left: 120 + frame * 2, top: 72,
    width: 12, height: 12, backgroundColor: '#e04040'}} />;
};
const OpenStreetMapTiles = () => {
  const frame = useCurrentFrame();
  return <AbsoluteFill style={{backgroundColor: '#dbe8ce', overflow: 'hidden'}}>
    {[0, 1, 2, 3, 4, 5].map(index => <Img key={index} src={staticFile(`tile-${index}.png`)}
      style={{position: 'absolute', left: (index % 3) * 128 - frame * 2,
        top: Math.floor(index / 3) * 128 - 32, width: 128, height: 128}} />)}
    <Marker />
  </AbsoluteFill>;
};
const MapKitSnapshot = () => <AbsoluteFill style={{overflow: 'hidden'}}>
  <Img src={staticFile('snapshot.png')} style={{width: 320, height: 180}} />
  <Marker />
</AbsoluteFill>;
registerRoot(() => <>
  <Composition id="OpenStreetMapTiles" component={OpenStreetMapTiles} width={320} height={180} fps={30} durationInFrames={30} />
  <Composition id="MapKitSnapshot" component={MapKitSnapshot} width={320} height={180} fps={30} durationInFrames={30} />
</>);

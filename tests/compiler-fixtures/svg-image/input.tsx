import React from 'react';
import {AbsoluteFill, Composition, registerRoot, useCurrentFrame} from 'remotion';

const Image = () => {
  const frame = useCurrentFrame();
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="8"><rect width="16" height="8" fill="${frame ? '#0000ff' : '#ff0000'}"/></svg>`;
  return <AbsoluteFill><img src={`data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`}
    style={{width:'100%',height:'100%',objectFit:'contain'}} /></AbsoluteFill>;
};
registerRoot(() => <Composition id="SVGImage" component={Image} width={32} height={32} fps={30} durationInFrames={2} />);

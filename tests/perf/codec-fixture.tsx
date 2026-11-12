import React from 'react';
import {Composition, registerRoot, useCurrentFrame} from 'remotion';
const Fixture = () => {
  const frame = useCurrentFrame();
  const color = ['#ff0000', '#00ff00', '#0000ff', '#ffffff', '#000000', '#ff00ff'][frame];
  return <div style={{width:64,height:64,backgroundColor:color,opacity:frame===5?0.5:1}} />;
};
registerRoot(() => <Composition id="CodecFixture" component={Fixture} width={64} height={64} fps={24} durationInFrames={6} />);

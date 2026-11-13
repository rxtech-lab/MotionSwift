// One-time rasterization of the real OSM vector basemap, shared by both renderers.
import React from 'react';
import {Composition, Img, registerRoot} from 'remotion';
import {artwork} from '../../Examples/MotionShowcase/Railway/artwork';
const Map = () => <Img src={artwork()} style={{width: 960, height: 540}} />;
registerRoot(() => <Composition id="RailwayBasemap" component={Map} width={960} height={540} fps={30} durationInFrames={1} />);
